# SSH module research and design

## Decision

Create one shared SSH module with two independent parts:

- a Home Manager client policy, safe on Linux and Darwin;
- an OpenSSH daemon policy, enabled only where the module system exposes
  `services.openssh`.

The module should set durable defaults. Local home and host modules should
continue to own identities, agent integration, jump hosts, per-service host
key files, listener addresses, ports, firewall rules, allowed accounts, and
root-login exceptions. Those choices are specific to a machine and its
recovery path.

The original split already followed this model: the Home Manager module owned
client defaults, the NixOS module owned daemon defaults, and the `local/ssh.nix`
files described actual destinations and host policy. The shared replacement
keeps that separation instead of turning one module into an inventory of
personal hosts.

## Client policy

`ssh` uses command-line settings first, then `~/.ssh/config`, then the system
configuration. It uses the first value found for each option. Host-specific
stanzas therefore need to come before `Host *`. This lets a Home Manager
configuration coexist with a system configuration and lets local per-host
settings override a shared default. [ssh_config(5)](https://man.openbsd.org/ssh_config)

Use these global Home Manager settings:

```nix
"*" = {
  ForwardAgent = false;
  ForwardX11 = false;
  Compression = false;

  ServerAliveInterval = 60;
  ServerAliveCountMax = 3;
  TCPKeepAlive = false;

  HashKnownHosts = true;
  StrictHostKeyChecking = "accept-new";
  UpdateHostKeys = "yes";

  ControlMaster = "auto";
  ControlPath = "~/.ssh/cm/%C";
  ControlPersist = "10m";
  ConnectTimeout = 10;
};
```

`accept-new` adds a host key on first contact but still rejects a changed key.
It is the right general default for a personal machine. For a small set of
important, pre-provisioned hosts, set `StrictHostKeyChecking = "yes"` locally
and manage their keys. Do not use `no`, which accepts changed host keys.
[ssh_config(5)](https://man.openbsd.org/ssh_config)

`HashKnownHosts = yes` hides host names and addresses if a user's
`known_hosts` file leaks. It does not rewrite existing entries, so a one-time
`ssh-keygen -H -f ~/.ssh/known_hosts` is needed if that cleanup is wanted.
[ssh_config(5)](https://man.openbsd.org/ssh_config)

`UpdateHostKeys = yes` accepts additional host keys only after a trusted host
key authenticated the server. It supports server key rotation and quietly does
nothing with pre-6.8 servers that do not implement the extension. It should
stay disabled for host stanzas that deliberately use a separate, disposable
`UserKnownHostsFile`, such as dynamically allocated compute nodes. Its `ask`
mode does not work with `ControlPersist`. [ssh_config(5)](https://man.openbsd.org/ssh_config)

Connection multiplexing avoids a handshake for each short-lived SSH, Git, or
remote-development command. `%C` includes the connection tuple and is a
supported safe control-socket token; its containing directory must be mode
0700 and not writable by another user. A multiplexed connection retains the
master connection's agent and X11 forwarding, another reason to keep those off
globally. [ssh_config(5)](https://man.openbsd.org/ssh_config)

Server-alive messages travel in the encrypted channel and cannot be spoofed.
They give stalled Wi-Fi and VPN sessions a predictable three-minute failure
time. `TCPKeepAlive = no` avoids kernel probes that may tear down a connection
during a brief routing failure. [ssh_config(5)](https://man.openbsd.org/ssh_config)

Keep `ForwardAgent`, `ForwardX11`, and compression off globally. A user able
to access a forwarded agent socket can ask that agent to authenticate, and
untrusted traffic sharing a compressed connection with trusted traffic can
reveal information about the latter. Turn these on only for a named host where
the workflow requires it. [ssh_config(5)](https://man.openbsd.org/ssh_config)

Do not place `AddKeysToAgent`, `UseKeychain`, `IdentityAgent`, `IdentityFile`,
`ProxyJump`, `User`, or `SetEnv` in the shared policy. They describe the
person's agent and destinations. `UseKeychain` is Apple's extension, so it
belongs in a Darwin-local stanza guarded with `IgnoreUnknown` when the same
home configuration can be evaluated on Linux.

## Daemon policy

Use the following portable baseline where the OpenSSH service is managed.
Keep authentication and forwarding controls firm. Use `mkDefault` only for
conservative availability choices that a host may deliberately override.

```nix
{
  PasswordAuthentication = false;
  KbdInteractiveAuthentication = false;
  PermitEmptyPasswords = false;
  PubkeyAuthentication = true;
  AuthenticationMethods = "publickey";

  X11Forwarding = false;
  AllowAgentForwarding = false;
  GatewayPorts = "no";
  PermitTunnel = "no";
  PermitUserEnvironment = false;

  Compression = false;
  TCPKeepAlive = false;
  ClientAliveInterval = 300;
  ClientAliveCountMax = 3;

  LoginGraceTime = 30;
  MaxAuthTries = 4;
  MaxStartups = "10:30:60";
  UseDns = false;
}
```

OpenSSH otherwise permits password authentication by default. Disabling both
password and keyboard-interactive authentication, while requiring `publickey`,
makes the baseline key-only. `UsePAM` is a platform integration choice and
should remain separate: it can provide session, account, and audit handling
without re-enabling the disabled SSH authentication methods. The available
authentication methods are evaluated in sequence, so a host that requires MFA
must locally replace `AuthenticationMethods` and re-enable the matching method.
[sshd_config(5)](https://man.openbsd.org/sshd_config)

The forward restrictions block agent, X11, tunnel, and non-loopback remote
listening exposure. Do not use `DisableForwarding` globally. It also disables
TCP and Unix-socket forwarding, which breaks common Git, development, and
administration workflows. It suits a restricted account in a host-local
`Match` block. Disabling TCP forwarding does not add useful protection to a
normal shell account because that user can run an equivalent forwarder anyway.
[sshd_config(5)](https://man.openbsd.org/sshd_config)

The admission limits reduce cheap unauthenticated connection pressure. Test
them with the host's expected traffic. `PerSourceMaxStartups = 3` is reasonable
for a workstation but may penalize users behind NAT and should be an opt-in
host setting rather than a universal daemon default. Do not set
`MaxSessions` below its default of 10 because `1` effectively disables client
multiplexing. [sshd_config(5)](https://man.openbsd.org/sshd_config)

Do not put `PermitRootLogin`, `AllowUsers`, `AllowGroups`, `ListenAddress`,
`Port`, or key sources in the shared module. A shared module may safely default
`openFirewall` and `startWhenNeeded` to `false`, but every host should state
its actual reachability and activation policy explicitly. For example,
`PermitRootLogin = "prohibit-password"` can be correct for a deploy or
break-glass key, while `no` is the right choice for many other machines. The
host needs to make that recovery decision. [sshd_config(5)](https://man.openbsd.org/sshd_config)

## Version and algorithm compatibility

Leave `Ciphers`, `MACs`, `KexAlgorithms`, `HostKeyAlgorithms`, and
`PubkeyAcceptedAlgorithms` unset. OpenSSH's maintained defaults include its
current cryptographic policy, and static lists prevent security improvements
from arriving with updates. This matters now: OpenSSH 10.0 removed DSA and
removed finite-field Diffie-Hellman from the server default because it is slow
and offers no advantage over ECDH or post-quantum key agreement.
[OpenSSH 10.0 release notes](https://www.openssh.org/txt/release-10.0)

Avoid new optional controls in a module expected to work with a system-supplied
macOS client or server. `PerSourcePenalties` arrived in OpenSSH 9.8 and is on
by default there; it may affect users behind NAT or a proxy. `ChannelTimeout`,
`UnusedConnectionTimeout`, `WarnWeakCrypto`, and post-quantum algorithm names
also depend on the installed OpenSSH version. In a shared config an unknown
server keyword can stop `sshd` from starting, so inherit a safe upstream
default instead of hard-coding a newer feature. [OpenSSH 9.8 release notes](https://www.openssh.org/txt/release-9.8)

The same restraint avoids a false security promise from a copied algorithm
list. OpenSSH 9.9 made the ML-KEM/X25519 hybrid key exchange available by
default, which is precisely the sort of upgrade a frozen list misses.
[OpenSSH 9.9 release notes](https://www.openssh.org/txt/release-9.9)

## Module shape and verification

The shared file is an envelope with separate NixOS, Home Manager, and
nix-darwin members. The framework exports only the applicable member, so one
selector works for NixOS, nix-darwin, and standalone Home Manager without
creating invalid option paths. Let Home Manager own the user client config when
it is present. Do not also generate a competing system-wide client
configuration for that user.

The client part needs to create the control-socket directory as part of Home
Manager activation with mode 0700. Keep the declaration user-relative, not
hard-coded to a particular account name.

After activation, inspect effective client options and validate the daemon on
each platform:

```sh
ssh -G example.com | sort
ssh -Q cipher
ssh -Q KexAlgorithms
sshd -t
```

Test one normal interactive session, Git over SSH, a local and remote port
forward where the host permits them, a changed host key rejection, host-key
rotation, and a Darwin machine that uses the system OpenSSH client. Test any
NAT or bastion environment before enabling per-source admission limits.
