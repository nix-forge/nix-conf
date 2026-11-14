# SSH from desktop to MacBook

The desktop configuration now provides `ssh macbook` and `ssh macbook-pro-m4`.
Both select `<USER>@<MACBOOK-HOSTNAME>` and the desktop's existing
`~/.ssh/id_ed25519` key. The MacBook configuration enables Apple's SSH server
and authorizes that desktop public key for `user`.

The desktop pins the MacBook's existing Ed25519 host key under the stable
`macbook` alias. This is the same public key already declared for the MacBook's
nix-seal host identity. A different host key is rejected even if the IP address
changes. Private keys are not copied between machines.

## One-time Mac setup, then remote deployments

These changes are saved in Nix configuration. On a MacBook that has never
activated the root SSH policy, activate it once from its own terminal:

From this checkout with these changes available:

```sh
sudo darwin-rebuild switch --flake .#macbook-pro-m4
```

After that, deploy from the desktop without a sudo prompt:

```sh
just macbook-deploy
```

The desktop uses resolve-only mDNS on its physical wired and wireless links to
find `<MACBOOK-HOSTNAME>`. It accepts mDNS replies from private IPv4 or link-local
IPv6 peers on those interfaces. Avahi and LLMNR remain disabled. This requires
both machines to share a network that permits Bonjour traffic.

UniFi Site Manager could not be inspected because the app's browser runtime
was missing its required `browser-service.mjs` file. No DHCP reservations or
other UniFi settings were changed. The Bonjour configuration therefore remains
the address-discovery method; a reserved LAN address can replace `HostName`
later without changing the host-key pin.

If the network blocks Bonjour, use the MacBook's current LAN address while
retaining the pinned host key and client settings:

```sh
ssh -o HostName=MACBOOK_LAN_IP macbook
```

The MacBook accepts the desktop's existing public key for both `user` and
root. Root SSH permits public-key authentication only. Its authorized key has
OpenSSH's `restrict` option, which disables forwarding and TTY access. Password
authentication remains disabled for every account. The `macbook-pro-m4`
deploy-rs node connects as root, so activation needs no sudo prompt.
The Mac's SSH configuration adds the Nix profile to root's noninteractive PATH,
which deploy-rs needs to access the remote Nix store and set the system profile.
An SSH connection opened before this policy was activated must be closed before
the first deployment.

The deployment commands connect over SSH themselves. There is no separate SSH
login step. `just macbook-deploy` builds and activates the configuration.
`just macbook-build` is an optional dry activation preview. Both create a fresh
[verified immutable source export](mac-source-exports.md), including tracked
working-tree changes and initialized dirty submodules. Local freshness and Mac
integrity are checked before and after the operation. New source files must be
added to Git before the default export selects them. `just mac-test` and
`just mac-check` use the same automatic export process for native tests and the
broader temporary-fix check. The MacBook must be reachable through the pinned
`macbook` SSH alias.

Before remote activation, enable **Allow full disk access for remote users** in
macOS System Settings > General > Sharing > Remote Login. The MacBook's Home
Manager profile copies application bundles, and its activation refuses to
update them over SSH without this permission. Apple documents the setting in
its [Remote Login guide](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac).

## Validation

The evaluated MacBook Bonjour name, SSH account, authorized public key, and
desktop host-key pin agree. Nix evaluates the complete macOS system derivation.
OpenSSH accepts the client and daemon configuration; nftables accepts the mDNS
rules in an isolated network namespace. Modified Nix files pass `nixfmt`.

The desktop reached the MacBook over pinned-key root SSH and completed a live
`just macbook-deploy`. The Mac's active system and system profile point to the
new deployment generation. The Darwin deploy-rs confirmation watcher did not
observe removal of its canary file, so this node disables `magicRollback`;
`autoRollback` remains enabled for activation errors.
