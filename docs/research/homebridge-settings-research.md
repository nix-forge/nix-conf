# Homebridge settings for the Raspberry Pi service

Reviewed: 2026-09-28. Scope: the NixOS Raspberry Pi 4 Homebridge service using
Homebridge 2.3.1 and UI 5.29.0. The question is which upstream settings improve
this deployment without breaking plugin and HomeKit behavior.

## Answer

Select Avahi explicitly for the bridge advertiser, start Homebridge after
Avahi, set the UI session timeout to one hour, restrict the state directory to
mode `0700`, and use the same Node.js version for package launchers and plugin
commands. Keep the existing Ethernet bridge
binding, loopback UI with form authentication, source-restricted HTTPS proxy,
locally generated pairing identity, systemd logging, and encrypted off-device
backups.

## Findings and sources

- [Homebridge's mDNS guide](https://github.com/homebridge/homebridge/wiki/mDNS-Options)
  recommends Avahi on Linux when Avahi and D-Bus are available. The
  [Homebridge v2 update guide](https://github.com/homebridge/homebridge/wiki/Updating-To-Homebridge-v2.0)
  says v2 selects Avahi by default if available and otherwise uses Ciao. The
  [Pi system module](../../hosts/nixos/raspberry-pi/local/system.nix) enables Avahi
  on `eth0` and D-Bus. An explicit `bridge.advertiser = "avahi"` makes discovery
  depend on that configured responder rather than startup-time detection. The
  [Homebridge module](../../hosts/nixos/raspberry-pi/local/homebridge/default.nix) now
  requires and starts after `avahi-daemon.service`.
- The same [mDNS guide](https://github.com/homebridge/homebridge/wiki/mDNS-Options)
  says `bridge.bind` affects the HomeKit TCP listener but does not limit Avahi's
  advertised addresses. The Pi's `services.avahi.allowInterfaces = [ "eth0" ]`
  is therefore the advertisement limit. It retains the explicit HomeKit port
  and Ethernet binding.
- The [UI configuration guide](https://github.com/homebridge/homebridge-config-ui-x/wiki/Config-Options)
  documents `sessionTimeout` in seconds with an eight-hour default, form
  authentication, and a wildcard default listening address. One hour is a
  local security and usability choice, not an upstream optimum. The Pi already
  binds the UI to loopback and terminates TLS at its restricted nginx proxy.
  The module's systemd log method and disabled UI terminal remain appropriate.
- The [NixOS service module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/services/home-automation/homebridge.nix)
  adds its host package set's Node.js to the service PATH. The Pi borrows its
  [Homebridge and UI packages](../../hosts/nixos/raspberry-pi/local/homebridge/default.nix)
  from a newer Nixpkgs input. Local evaluation found their launchers use Node
  24.20.0 while the vendor host package set supplies Node 24.18.0. Putting
  the newer input's Node.js first in the service PATH aligns plugin commands
  and child processes with the package launchers.
- The [systemd directory documentation](https://www.man7.org/linux/man-pages/man5/systemd.exec.5.html)
  says `StateDirectoryMode` defaults to `0755` and applies the configured mode
  to an existing directory on service start. The upstream NixOS service sets
  `StateDirectory = "homebridge"` without a mode. The Pi now sets
  `StateDirectoryMode = "0700"` because that tree holds pairing state, plugin
  data, and UI authentication. Its existing `UMask = "0077"` governs new files.
- The NixOS module permits UI-managed plugins in a writable directory and
  includes native build tools, broad service capabilities, and passwordless
  host controls. The [Homebridge child bridge guide](https://github.com/homebridge/homebridge/wiki/Child-Bridges)
  describes per-plugin process isolation and additional resource use. No
  generic memory limit, child bridge policy, capability drop, or blanket
  sandbox setting is justified without checking the installed plugins and
  testing their hardware and network access. Child bridge HAP ports need
  explicit firewall rules when configured.
- The [mDNS guide](https://github.com/homebridge/homebridge/wiki/mDNS-Options)
  also documents a possible IPv4 port 5353 conflict with Homebridge's separate
  Matter responder. `bridge.matter.disableIpv4` is a conditional remedy if
  `.local` resolution breaks. It is not enabled merely because Avahi is used.

## Validation and limits

Nix evaluation of the Pi configuration confirms `advertiser = "avahi"`,
`sessionTimeout = 3600`, `avahi-daemon.service` in Homebridge's `Requires` and
`After`, `StateDirectoryMode = "0700"`, and Node 24.20.0 first in its service
PATH. The Pi system closure built successfully on `desktop` with
`workstation-task nix build` for the `aarch64-linux` configuration. These checks
do not establish service startup or HomeKit discovery. The plugin inventory and
Matter use were not reviewed. After activation, verify Avahi and Homebridge startup,
`_hap._tcp` discovery from intended VLANs, a real accessory in Apple Home,
UI login and session expiry, and plugin installation under the aligned Node.

## Implication for this repository

The selected settings live in the [Pi Homebridge module](../../hosts/nixos/raspberry-pi/local/homebridge/default.nix).
Keep plugin-specific ports and resource limits out of the base configuration
until a plugin requires them and its behavior can be tested.
