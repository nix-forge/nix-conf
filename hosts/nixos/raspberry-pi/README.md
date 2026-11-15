# Raspberry Pi host

A minimal Raspberry Pi 4 system with Homebridge and a Scrypted live-view trial.
The host has no workstation profile or video recorder.

## Configuration ownership

- `default.nix` selects SSH, disko, Pi boot support, and the standalone
  `nix-homelab` IoT and LAN HTTPS modules.
- `local/disko.nix` describes the onboard microSD, with 1 GiB FAT firmware and ext4 root.
  The root partition has the legacy bootable GPT attribute so U-Boot scans its
  `/boot/extlinux/extlinux.conf`.
- `local/system.nix` owns accounts, Ethernet DHCP, firewall, logging and maintenance.
- `local/iot-lan.nix` adds an optional tagged IoT address for devices that
  reject control from a routed subnet.
- `local/homebridge/default.nix` selects Homebridge packages, bridge ports, interface,
  and sealed UI credential paths.
- `local/homebridge/integrations.nix` selects pinned Homebridge plugin packages.
- `../../../nix-homelab/modules/iot/` owns pairing initialization, managed UI
  login, plugin reconciliation, and Scrypted service behavior.
- `local/https.nix` owns the Pi's certificate and shared HTTPS firewall policy.
- `local/homebridge/https.nix` serves the Homebridge administration UI.
- `local/scrypted/default.nix` selects the pinned Scrypted package and Pi resource limits.
- `local/scrypted/https.nix` serves its administration UI through the Pi proxy.
- `local/nix-seal.nix` declares the Pi's sealed DNS and UI credentials and target identity.
- `../../shared/local/network.json` owns the Pi reservation and HTTPS client address policy.
- `keys/` contains public administration keys only.
- `../../shared/local/flake/raspberry-pi.nix` composes the host with the root Nixpkgs
  pin shared with the desktop and exposes installer and provisioner packages.

The Pi uses the root Nixpkgs revision for its NixOS modules and ordinary
packages, matching the desktop. `nixos-raspberrypi` supplies the Pi 4 boot
modules and a matching kernel and firmware bundle from its own tested Nixpkgs
pin. This narrow hardware pin matches the vendor's signed binary cache and
avoids compiling the kernel under emulation. The Pi opts into that cache through
the shared cache policy; the root flake also lists it for the first build.
Review the closure when either input changes, retain a recovery path, then
verify boot and Homebridge on the Pi. The Pi's `system.stateVersion` remains at
its installation value.

## Administration

The normal account is `ianmh`. Root key access is available for installation,
recovery, and deploy-rs. Password authentication is disabled; the wheel account
can use sudo without a password. Disk encryption is not configured, allowing
unattended reboot on this headless system. Protect physical access to its card.

On the Trusted LAN or the home WireGuard VPN, open
`https://homebridge.<HOMELAB_DOMAIN>` for the Homebridge UI. The Pi's own nginx
proxy and DNS-01 wildcard certificate serve HTTPS, so its UI and HomeKit
service continue when the desktop is off. Cloudflare holds a DNS-only
exact A record pointing to the Pi's private reserved address; no Cloudflare
proxy, tunnel, router port forward, or public HTTP validation is involved. The
Pi firewall admits TCP 443 only from the Trusted LAN and WireGuard subnet;
nginx repeats that source policy, and the Homebridge UI remains bound to
loopback TCP 8581. The DNS API
token is a root-only sealed secret used by ACME; the certificate is renewed on
the Pi. When rotating the shared DNS credential, rekey both host declarations.

For same-subnet TV control, keep the management VLAN native on the Pi's switch
port and permit only the IoT VLAN as tagged traffic. The tagged interface
receives an IPv4 address by DHCP
without adopting its gateway or DNS servers. It has no inbound firewall ports;
the Homebridge UI and main HomeKit bridge stay on the management interface.
When moving the Pi to another switch port, give that port the same native and
tagged VLAN policy. Without the tag, the Pi still boots and its management
connection remains available, but same-subnet TV control cannot work.

Scrypted runs as a native systemd service using the pinned package in `pkgs/`.
Its state remains in `/var/lib/scrypted`, and nginx proxies its administration
UI over loopback. Use `https://scrypted.<HOMELAB_DOMAIN>` on the Trusted LAN
or the home WireGuard VPN.
The Pi's existing address serves both HTTPS sites; no second address or DHCP
exclusion is needed. The firewall blocks direct access to Scrypted's own admin
ports. The service has memory and process limits and no recording service.
Back up its state encrypted before server or plugin upgrades.

Scrypted's sole administrator username and password come from nix-seal. Before
the server starts, the homelab
[`scrypted-auth.cts`](../../../pkgs/pkgs/by-name/ho/homelab-iot-scripts/scrypted-auth.cts)
reconciles that account in its
database using Scrypted's password setter. It tracks digests of the sealed
credential and Scrypted's user token, so an unchanged account keeps its sessions
across restarts even if Scrypted changes its password hash format. A sealed
password or username change invalidates existing sessions; an unexpected second account
stops startup for review. The Pi system build runs the account compatibility
check against its selected Scrypted package; the same check is available as
`scrypted-auth-compat` in the flake checks. Prepare and transfer signed secret
artifacts before deploying a credential change. Reveal the credentials with
`nix-seal secret reveal` on an administrator machine; password changes made in
the UI will be replaced at the next service start.

The `scrypted-plugins` unit installs pinned WebRTC, Snapshot, Rebroadcast,
Arlo, and HomeKit plugins after Scrypted starts. Arlo and HomeKit use published
plugin artifacts packaged in `pkgs/`. Arlo's Python requirements install into
the plugin state directory on first launch. Check both service journals after
deployment and back up the state before plugin upgrades.
Removing a plugin declaration does not uninstall it or erase devices. Review
its devices and uninstall it in Scrypted before deleting its state.
The plugins are installed without an Arlo account or paired cameras. Scrypted's
pre-start hook sets HomeKit's mDNS advertiser to Avahi, binds advertisements
to the Pi's server address, and disables Scrypted's plugin autoupdater so it
cannot replace Nix-pinned releases. The Arlo plugin defaults to manual two-factor
sign-in, MQTT events, and disabled security-mode controls. Keep those defaults
until the cameras have been tested. Configure email or SMS as the Arlo account's
default second factor, then enter the account credentials and code in the
Scrypted UI. Do not put Arlo credentials in Nix settings.

For each camera, verify live video and motion in Scrypted first. Start with the
Arlo WebRTC stream, HomeKit's default RTP sender, and the Rebroadcast mixin.
Use the same Arlo stream for every Scrypted consumer because Arlo permits only
one active stream per camera. Test Cloud RTSP only if WebRTC connection time is
unacceptable; RTSP may need audio transcoding for HomeKit. Keep prebuffering off
for battery or solar cameras. Enable it only after testing a continuously powered
camera and checking memory use. Arlo's smart detection and cloud or local
recording may contend for the same stream; review those Arlo app settings with
the owner before changing them. Scrypted NVR is not installed, so this host has
no local video recording.

Do not pair the empty Scrypted bridge in Apple Home while there are no cameras.
Use HomeKit's default standalone accessory mode and each camera's own pairing
code after it appears in Scrypted. In the camera's Scrypted HomeKit settings,
open Pairing and scan its QR code with the Apple Home app. Set a stable accessory
port and admit that port from the intended HomeKit clients before pairing. The
Pi firewall currently blocks unconfigured accessory ports, including the empty
Scrypted bridge. Pair one camera and verify live video, motion notifications,
and HomeKit discovery from the Apple home hub before adding the rest. Keep the
default HomeKit video transport unless a tested camera requires a different one.
The cloud stream path and cross-VLAN pairing may add latency or fail for particular
cameras. See the [Arlo plugin guidance](https://github.com/scryptedapp/arlo#general-setup-notes)
and [Scrypted HomeKit guide](https://docs.scrypted.app/homekit.html) for current
camera-specific advice.

For local recovery, open a temporary SSH tunnel:

```sh
ssh -L 8581:localhost:8581 ianmh@<PI_ADDRESS>
```

Open `http://localhost:8581`. Homebridge TCP 51826 and mDNS UDP 5353 are available
on Ethernet; TCP 8581 is not opened in the host firewall. Each child bridge needs
an explicitly chosen port and a corresponding firewall rule.

The UI uses form authentication. Its administrator username and password come
from the Pi's nix-seal secrets. On startup, Homebridge reconciles that account
in `auth.json` and preserves its two-factor enrollment. A changed sealed
password invalidates existing UI sessions. Prepare the Pi's signed secret
artifacts before deploying a generation that changes either credential.
The UI session expires after one hour. Homebridge uses the Pi's Avahi daemon
for HomeKit advertisement on Ethernet; the service starts after Avahi. The
Homebridge service PATH selects the same Node.js release as its Nix packages
for plugin installs and child processes.

The startup check requires one UI account; review additional accounts before
activation instead of silently leaving their passwords unmanaged.
Enable two-factor authentication in the UI after enrolling an authenticator.
Do not use the UI's core update button:
Nix owns Homebridge and UI versions. Review plugin permissions and source before
installing plugins, since their code runs with the Homebridge service account.

Homebridge core and UI are supplied by Nix. Plugins installed through the UI,
plugin credentials, accessory state, and pairing identity are mutable under
`/var/lib/homebridge`, whose service state directory is mode `0700`. Do not put
credentials or a pairing PIN in Nix settings.
Back up Homebridge and Scrypted state encrypted off-device before updates that
change plugin state. A NixOS generation rollback does not undo plugin data
migrations. The desktop's `raspberry-pi-homebridge-backup.timer` retains its
historical name but now pulls both state directories weekly, compresses and
encrypts them on the desktop, and catches up when the desktop returns online.
The archive is taken while the services run, so stop them for a consistent
pre-upgrade backup. A manual encrypted backup was taken before the earlier
Homebridge upgrade. Inspect backup growth when adding plugins; automatic
pruning is not configured. Restore only after stopping the affected service
and reviewing the files to be replaced.

Samsung Tizen, LG ThinQ, VeSync, and Blueair plugins come from the
personal package repository and link into `node_modules` at service startup.
Change their versions in Nix, not in the UI. Their accessories are not
configured until account authorization or local pairing succeeds. If an
existing mutable plugin has the same name, startup stops rather than deleting
it. The Blueair plugin lists the Blue Pure 511i Max as a tested device. The
[device integration review](../../../docs/research/raspberry-pi-device-integrations-research.md)
records model and API limits.

Use the Homebridge UI to authorize LG ThinQ after checking the devices in its
vendor app. The selected LG fork exposes laundry status, not direct washer or
dryer controls. VeSync uses two target-local nix-seal secrets. Homebridge reads
them from systemd credential files, and its startup migration replaces any
inline VeSync login in `config.json` with those file paths. Rotate the sealed
values and prepare signed Pi artifacts before deploying an account change;
editing VeSync credentials in the Homebridge UI will be reverted at restart.
Keep account values out of Nix settings and the store.

Configure Blueair through the Homebridge UI after verifying the purifier in
the Blueair app. Its plugin uses the Blueair cloud account. Leave UI debug and
verbose logging off during normal operation. Upstream warns that PM2.5 values
can be inaccurate; compare them with the vendor app before using them in an
automation. Choose a polling interval appropriate to the room rather than
polling faster than the default 15 seconds. No account password, discovered
device ID, or cloud token belongs in Nix settings.

## Build and deploy

Build from the desktop through the workload runner. The dedicated Pi recipe
adds AArch64 to its child Nix processes while preserving existing platforms;
the global desktop policy keeps emulated builds disabled. Its binfmt interpreter
uses QEMU user mode for cache misses. The recipe first copies the Pi kernel
from the vendor's signed cache, so a cache miss stops the build before Nix can
compile that kernel. Deploy-rs then copies the completed closure over SSH and
activates it on the Pi:

```sh
just raspberry-pi-build
just raspberry-pi-deploy
```

The deploy-rs node uses the reserved address and `remoteBuild = false`. Direct
closure transfer avoids destination substitution from caches outside the Pi's
narrow trust set. The Pi's one-job, two-core limit applies only to manual local
builds. The kernel, modules, and firmware remain on the vendor's tested pin.
Inspect the substitution plan when updating either Nixpkgs pin. NixSeal is
pre-1.0 and has not completed its external security audit.

## Installation

Nixos-anywhere is pinned and available as a package:

```sh
workstation-task nix run .#raspberry-pi-provision -- \
  --flake .#raspberry-pi --build-on local --target-host root@<INSTALLER_ADDRESS>
```

That destructive command requires a compatible installer booted from separate
media, so `/dev/mmcblk0` is not the installer's live root disk. The previous
Debian kernel cannot kexec. A customized Pi 4 installer image with the public
administration keys is exposed as
`packages.aarch64-linux.raspberry-pi-installer`.

The initial single-card installation was prepared offline on the desktop.
An installer-only disko extension selected the verified USB card and mounted
its partitions at a dedicated temporary root. The system closure was copied
to that root; the Pi firmware, U-Boot binary, and extlinux boot menu were
installed with native desktop tools using the built system's bootloader
inputs. The target `/etc` was initialized inside a chroot. Both filesystems
were checked after unmounting. The final bootloader step required no changes
to the desktop's binary-format handlers. For a future reinstall, prefer the
separate-media installer and nixos-anywhere command above. Never use the host's
`/dev/mmcblk0` setting to select a removable desktop device.

After first boot, verify SSH, DHCP, Homebridge, memory, temperature, and a clean
reboot. HomeKit across VLANs also needs gateway mDNS scope and firewall policies;
the Pi's Avahi instance does not reflect traffic between VLANs. A DHCP reservation
follows the Pi's Ethernet identity, while the access VLAN follows its switch port.
The Pi firewall admits SSH and HTTPS only from the management CIDRs in
`hosts/shared/local/network.json`, and Homebridge HomeKit TCP only from the trusted LAN CIDR.
It does not open these ports to the Pi's routed IPv6 address. If a home hub is
on another network, add its verified client CIDR to the HomeKit firewall rule
and the corresponding gateway policy before pairing.
In UniFi's Custom mDNS Proxy settings, include Servers alongside Trusted and IoT
and forward `_hap._tcp.local`, preserving discovery services already in use.
The current Service Scope is All; review it if more services are placed on the
Servers VLAN, since their mDNS advertisements would also cross these VLANs.
