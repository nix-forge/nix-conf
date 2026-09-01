# oo7 instead of GNOME Keyring

## Recommendation

Do not switch this desktop to oo7 yet.

oo7 is a credible replacement for the Secret Service part of GNOME Keyring. It
implements `org.freedesktop.secrets`, includes a sandbox-oriented Secret
portal, and supports PAM unlock and password rotation. It is not a replacement
for GNOME Keyring's other jobs, including its SSH agent and PKCS#11 support.
See the upstream [component list](https://github.com/linux-credentials/oo7/blob/0.6.0/README.md#L5-L18)
and the [Secret Service specification](https://specifications.freedesktop.org/secret-service-spec/latest/).

The desktop's current Nixpkgs revision packages oo7 0.6.0, as shown by the
[pinned derivation](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/oo/oo7/package.nix#L12-L27).
That release is a poor fit for this host's password-gated, headless greetd
session. The NixOS module starts `oo7-daemon` from `default.target` and also
enables PAM only for `login`; it does not arrange that the daemon receives the
Hyprlock password before it begins discovering and creating keyrings.
[NixOS module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/services/desktops/oo7.nix#L11-L37)

That ordering matters. oo7 0.6.0 creates a locked `Login` collection when it
starts without a discovered default collection. Its migration code creates a
locked placeholder if migration cannot run with a secret. The later PAM handoff
can therefore collide with state that started before the password arrived.
[Default-collection creation](https://github.com/linux-credentials/oo7/blob/0.6.0/server/src/service/mod.rs#L671-L713)
[v0 migration fallback](https://github.com/linux-credentials/oo7/blob/0.6.0/server/src/service/mod.rs#L587-L664)

The release's PAM `auto_start` path also directly execs `/usr/bin/oo7-daemon`.
Upstream recorded that this fails under greetd when package paths or the target
user's runtime environment differ. The issue was fixed after 0.6.0, but there
is no newer oo7 release to consume as of 2026-08-26.
[0.6.0 source](https://github.com/linux-credentials/oo7/blob/0.6.0/pam/src/socket.rs#L133-L177)
[greetd issue](https://github.com/linux-credentials/oo7/issues/516)
[latest release](https://github.com/linux-credentials/oo7/releases/latest)

The practical result is worse than a prompt: browser and CLI credentials may
be unavailable or rewritten while the Secret Service is in an inconsistent
state. This is exactly the wrong place to accept an integration race.

There is no credible performance case for switching. Neither upstream nor
Nixpkgs publishes a comparative latency, memory, or throughput benchmark. The
user-visible cost here is dominated by D-Bus, keyring file encryption, and the
application doing the credential request. Choose a provider for correctness
and integration, not a presumed Rust speedup.

## What is good about oo7

The direction is sound. The daemon implements the standard Secret Service API,
and its shipped user unit has no network access, no new privileges, private
devices and temporary files, a read-only system view, and memory-execution
protection. NixOS gives the daemon only `CAP_IPC_LOCK`, so it can try to keep
secrets out of swap without broadly elevating it.
[Upstream unit](https://github.com/linux-credentials/oo7/blob/0.6.0/server/data/oo7-daemon.service.in)
[NixOS capability wrapper](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/services/desktops/oo7.nix#L27-L34)

PAM integration is also designed around the normal desktop UX. It captures the
login password in the `auth` stack, hands it to the daemon during `session`,
and updates matching keyrings during password changes. The module is optional,
so a keyring failure cannot reject an otherwise valid login.
[PAM guide](https://github.com/linux-credentials/oo7/blob/0.6.0/pam/README.md#L40-L80)

The current upstream tree improved its socket checks. It validates the socket
type and owner before sending a password, and the listener permits only root
or the session user. Those changes are not in the pinned 0.6.0 release, so
they are evidence of progress, not a reason to deploy it now.
[PAM client on main](https://github.com/linux-credentials/oo7/blob/main/pam/src/socket.rs#L265-L345)
[PAM listener on main](https://github.com/linux-credentials/oo7/blob/main/server/src/pam_listener/mod.rs#L94-L177)

## Gaps that matter here

oo7 has no SSH-agent component. The existing `gcr-ssh-agent` NixOS option is
not a safe migration companion: its default package is GCR 4, while Nixpkgs
builds GCR 4 with its SSH agent disabled and notes that it still relies on
GNOME Keyring's agent. A real migration needs a separate agent decision,
normally OpenSSH's agent or a hardware-token agent. Do not leave two agents
competing for `SSH_AUTH_SOCK`.
[GCR agent module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/services/desktops/gnome/gcr-ssh-agent.nix)
[GCR package setting](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/gc/gcr/package.nix#L78-L85)

oo7's upstream issue tracker still has an open design issue for preserving an
unlocked keyring across a daemon restart. A package update or crash can return
the user to a locked keyring in the same graphical session. That is not a
security failure, but it is a real UX regression for a workstation with
lingering user services.
[Restart-continuity issue](https://github.com/linux-credentials/oo7/issues/548)

Passwordless-only PAM login is also incompatible with automatic unlock when
the authenticator never sets `PAM_AUTHTOK`. That does not affect the current
password-gated Hyprlock plan, but it rules out treating oo7 as future-proof
for a FIDO2-only login flow.
[Upstream explanation](https://github.com/linux-credentials/oo7/issues/504)

## Future configuration shape

When a released oo7 version includes the greetd and lifecycle fixes, use the
built-in NixOS module rather than hand-writing a service. The intended shape
is below. It is a review checklist, not a configuration to apply against
0.6.0.

```nix
{
  services.oo7.enable = true;
  services.gnome.gnome-keyring.enable = false;

  # oo7 has no SSH agent. Pick one independent provider.
  services.gnome.gcr-ssh-agent.enable = false;
  programs.ssh.startAgent = true;

  security.pam.services = {
    # services.oo7 enables this one itself.
    login.oo7.enable = true;

    # Match every password-authenticated entry point that should unlock the
    # keyring and maintain its password.
    hyprlock.oo7.enable = true;
    passwd.oo7.enable = true;
  };
}
```

This preserves the good UX goal: one password unlocks the desktop and Secret
Service, and `passwd` changes both passwords together. The separate OpenSSH
agent preserves a single `SSH_AUTH_SOCK`; the existing `AddKeysToAgent = yes`
policy can load a key at first use, but it does not match GNOME Keyring's
saved-key UX. Expect an SSH passphrase prompt after login unless the chosen
agent has an explicit hardware-token or desktop-prompt integration. Do not set
an empty keyring password or save the keyring password in systemd's encrypted
credential store as a workaround. oo7 documents that root or another user able
to read that credential and access the TPM may decrypt it.
[NixOS PAM option](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/security/pam.nix#L681-L688)
[Credential-store warning](https://github.com/linux-credentials/oo7/blob/0.6.0/server/README.md#L9-L30)

Before any future switch, make a private backup of
`~/.local/share/keyrings`, test in a disposable user account first, and verify
browser, `gh`, `glab`, SSH, and a password change before declaring it done.
oo7 writes a new v1 keyring and a `.migrated` marker, leaving the legacy file
present, but that still makes rollback and comparison work that should be
tested rather than assumed.
[Migration implementation](https://github.com/linux-credentials/oo7/blob/main/server/src/migration.rs#L37-L58)
