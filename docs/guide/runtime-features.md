# Reusable runtime features

These features were extracted from local host and home configuration. The
consuming target supplies network endpoints, credential producers, hardware
selection and account policy. Each feature can be selected independently.

The [feature catalog](features.md) links the complete module sources. In this
repository, select a feature in the target's `default.nix` and put its option
values in `local/`. An external configuration can import the linked source file
into the matching NixOS or Home Manager module class. The Jujutsu and IWD modules
use `myLib.python.notificationProcess`; supply `myLib` by importing this
repository's `lib/default.nix` with your package set's `lib`. Rust editor support
also needs the pinned `inputs.nix4vscode` input. See the
[composition architecture](architecture.md) for these module arguments.

## Supervised SSH forwards

Select `services-ssh-forwards` in a home profile. Each named entry owns one
foreground SSH process and one local or reverse TCP forward:

```nix
services.sshForwards.music = {
  host = "music.example.test";
  bindPort = 14533;
  targetPort = 4533;
};
```

The listener defaults to `127.0.0.1`. A non-loopback listener requires
`acknowledgeExposure = true`. IPv6 addresses are accepted without brackets;
the module adds brackets to the forwarding specification. Exact duplicate
listener declarations are rejected. Aliases and overlapping wildcard bindings
still need operator review and native SSH validation.

Authentication and known-host provisioning remain ordinary SSH configuration.
The service enforces batch mode and strict host-key checking and disables shared
multiplexed sessions. Its selected SSH configuration must not add unintended
forwards. `direction = "remote"` creates a reverse listener; the server's
`GatewayPorts` setting also controls its exposure. A running forward proves
neither backend readiness nor application health.

Linux uses a systemd user service. macOS uses launchd and private log directories
under `xdg.stateHome/ssh-forwards`. macOS defaults to Apple's client for Keychain
integration; set `package = pkgs.openssh` when the selected SSH configuration
requires the Nix client. Set an entry's `enable = false` to remove its service.

## Protected Jujutsu identity

Select `dev-jj-identity` and enable the feature:

```nix
programs.jujutsu.runtimeIdentity = {
  enable = true;
  sourceFile = "/run/credentials/jujutsu-identity.toml";
  activationAfter = [ "provideIdentity" ];
};
```

The credential producer supplies private TOML containing only `[user]`, `name`
and `email`. The installer validates ownership, permissions and content, then
atomically links the runtime source into Jujutsu's `conf.d`. It preserves a live
provider path across credential generations. The source's parent directories
must also remain under the credential producer's control.

With `sourceFile = null`, activation reads the enabled Git configuration and
writes a private fragment. An empty Git identity removes the fallback fragment.
Signing keys, signer policy and credential production remain separate settings.
Repository configuration and environment overrides can still change Jujutsu's
final identity.

## Rust editor support

Select `vscode-languages-rust`. This selector imports its VS Code owner and
installs rust-analyzer with formatting and Clippy defaults. Set
`programs.vscode.rust.analyzerPackage`, `allTargets` or `denyWarnings` to vary
those choices. Ordinary `programs.vscode.profiles.default.userSettings`
assignments override the defaults, including the check command and formatter.
The module does not install a Rust toolchain or set remote editor paths.

## Activation safety

Select `system-activation-safety` on NixOS:

```nix
system.activationSafety.enable = true;
```

The native pre-switch hook shows the generation diff and checks the running
hostname against `networking.hostName`. `showDiff` and `checkHostname` can be
selected separately. Initial installation without a booted generation permits
the configured hostname. `EXPECTED_HOSTNAME` permits an intentional migration.
NixOS's `NIXOS_NO_CHECK` bypass still applies, so this is an operational guard.

## Runtime IWD profiles

Select `network-iwd-profiles` on NixOS:

```nix
networking.wireless.iwd.runtimeProfiles.office = {
  source = "/run/credentials/wifi-profile";
  afterUnits = [ "provide-wifi-credentials.service" ];
};
```

The runtime file starts with `SSID=<network name>` followed by native IWD
sections. Its contents stay outside the store. `profileType` accepts `psk`,
`8021x` and `open`. The module enables IWD by default and leaves IP management
to the host. Logical profile identifiers do not reveal the SSID.

The installer uses IWD's ELL parser for native structure, including embedded PEM
certificates. IWD still owns authentication semantics and certificate trust.
Protected root-owned sources may be provider-managed links. The installer
creates mutable private profiles atomically using IWD's exact SSID filename
encoding. Invalid input preserves the last working file. Missing optional
credentials skip provisioning without deleting that file.

`afterUnits` are soft provisioning dependencies. Restarting IWD or a declared
producer reruns provisioning. When a producer changes a file without restarting
its unit, explicitly restart the generated `iwd-office-profile.service`.
Provisioning units must precede IWD and must not depend on the profile unit.
Changing an SSID creates a new native profile; retire obsolete profiles
explicitly because IWD also owns user-created network state.

## Adaptive I/O cost

Select `hardware-iocost` on NixOS:

```nix
hardware.ioCost = {
  enable = true;
  kernelDevicePatterns = [ "nvme[0-9]*n[0-9]*" ];
};
```

Select whole disks explicitly. The module reconciles existing disks and handles
udev add/change events. It checks controller availability and preserves measured
hwdb policies and explicit `ctrl=user` settings. It selects the kernel's adaptive
model rather than assigning device-specific performance coefficients.

Configure slice or service `IOWeight` separately. Controller enablement does not
prove workload fairness; that requires measurements on the actual storage stack.

## Graphical authentication agent

Desktop applications use Home Manager's native `services.polkit-gnome` module.
It follows `graphical-session.target` and requires systemd user supervision.
Consumers can disable it when another agent owns authentication. System Polkit
authorization rules remain host policy.

The migration changes the agent unit to `polkit-gnome.service`. Its conflict with
the former `polkit-gnome-authentication-agent-1.service` stops the legacy agent
when the native unit starts. Activation and an interactive authentication prompt
remain native runtime checks.
