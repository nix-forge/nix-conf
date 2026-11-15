# Raspberry Pi Homebridge deployment

Reviewed: 2026-09-27. Scope: Raspberry Pi 4 or 5, Homebridge, NixOS,
nixos-anywhere, deploy-rs, and this repository's nix-homelab integration.

## Answer

Use a minimal `aarch64-linux` Pi host in `hosts/nixos/`, with native
Homebridge as the first choice after checking the actual plugins. Build updates
on another machine. Use deploy-rs for ongoing activation and a compatible NixOS
installer image for initial access. Nixos-anywhere is optional installation
automation after bootstrapping the installer.

Keep hardware, disks, SSH, secrets, and backup destinations in the host. There is
no need to extend nix-homelab for the initial Homebridge service. Additional
services can be selected independently on the same host. If home automation
becomes a reusable service family, add an optional Homebridge module there while
keeping the Pi host here. These are separate ownership decisions.

The deployed board is a Pi 4 Model B with about 1.8 GiB usable RAM and a
microSD card. The selected device families and integration gates are recorded
in the [device integration review](raspberry-pi-device-integrations-research.md).
Arlo cameras require the separate camera decision below. Bluetooth and USB
radios also require compatibility checks.

## Board support and installation

Current [nixos-hardware Raspberry Pi documentation](https://github.com/NixOS/nixos-hardware/blob/master/raspberry-pi/README.md)
includes Pi 4 and Pi 5 profiles. Its Pi 5 U-Boot path boots from SD, but cannot
drive USB, PCIe, or RP1 before Linux. Consequently, USB or NVMe boot and a USB
keyboard at the U-Boot prompt are unavailable through that path. SD boot with a
root filesystem on storage accessed by Linux is a different arrangement and
needs explicit initrd and mount validation.

For Pi 4, start with a current compatible AArch64 NixOS image and the matching
hardware profile. For Pi 5, choose the boot method deliberately. The
[nixos-raspberrypi project](https://github.com/nvmd/nixos-raspberrypi)
provides board installer images, kernel/firmware integration, and a cache. Its
README recommends the generation-aware `kernel` boot method for new Pi 5
installations. This is a useful candidate for a Pi 5 appliance, especially when
the SD U-Boot limitations conflict with the storage plan. Pin a compatible
revision and test boot, rollback, and the actual storage device before treating
it as an unattended appliance. Align its Nixpkgs revision with its documented
cache expectations; forcing it to follow an unrelated pin may cause rebuilds.

Search results and cached wiki pages contradicted each other about generic Pi 5
support during this investigation. The recommendation uses current upstream
hardware source and the board-specific project's documented boot paths, rather
than assuming any generic image will work.

[Nixos-anywhere's requirements](https://nix-community.github.io/nixos-anywhere/)
distinguish machines that can kexec an installer from machines already running
a suitable NixOS installation environment. The board-specific project explicitly
reports kexec unsupported. Plan to flash and boot compatible installation media,
obtain SSH access, and then either install directly or run nixos-anywhere with
Disko and a board-aware configuration. Do not promise a standard SSH-only
Raspberry Pi OS conversion. Use separate installer media when repartitioning the
target disk. Disko describes partitions; it does not supply Pi boot support.

## Homebridge runtime

The repository's locked Nixpkgs revision contains a
[native Homebridge module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/services/home-automation/homebridge.nix).
It runs Homebridge and its UI as a system service and stores state under
`/var/lib/homebridge`. It merges declared settings into mutable configuration and
allows npm plugins in a writable directory. Its runtime includes a compiler and
make for plugin installation. Enabling the service does not make plugin versions
declarative. Keep credentials out of Nix settings rendered into the store.

Prefer this native service for a small compatible plugin set. Test each plugin's
native binaries and external tools on ARM64 NixOS. For stronger reproducibility,
package the selected plugins with locked dependencies and explicit runtime
tools, then supply a verified plugin tree. Otherwise record exact plugin
versions, retain recovery backups, and regard plugin updates as separate changes.
Avoid core updates through the UI when Nix owns the core packages.

### Current package and UI findings

Before the package update on 2026-09-27, evaluating this repository's Pi configuration returned
`pkgs.homebridge.version = 2.0.2` and
`pkgs.homebridge-config-ui-x.version = 5.22.0`. The first-party
[Homebridge releases](https://github.com/homebridge/homebridge/releases) list
2.3.1, and the [UI releases](https://github.com/homebridge/homebridge-config-ui-x/releases)
should be checked before selecting a compatible update. This establishes a
version gap in the current pin; it does not prove the installed packages are
broken or that an untested package update is safe. Nixpkgs source trees already
available locally include newer Homebridge and UI recipes. Prefer a compatible
upstream Nixpkgs revision or a narrow package override after build and runtime
verification, with a personal package only when upstream does not provide a
usable version. The implementation selected the root upstream Nixpkgs packages,
Homebridge 2.3.1 and UI 5.29.0, while retaining the vendor Nixpkgs pin for Pi
boot support. Both packages were substituted from the upstream binary cache,
built into the Pi closure, activated, and tested after a reboot. No personal
package was needed.

The [Homebridge UI project](https://github.com/homebridge/homebridge-config-ui-x)
documents `admin`/`admin` as its default login. Change this during first-run
setup before widening access beyond a local tunnel. Its
[configuration options](https://github.com/homebridge/homebridge-config-ui-x/wiki/Config-Options)
include form authentication, a `host` binding (default `0.0.0.0`), and a
session timeout. Keep form authentication enabled, bind the UI to loopback,
and put a LAN-restricted HTTPS reverse proxy in front of it. The first-party
[reverse proxy example](https://github.com/homebridge/homebridge-config-ui-x/wiki/Reverse-Proxy%3A-Nginx-and-SSL)
passes the `Host`, forwarding, and WebSocket Upgrade headers needed by the UI.
The project's UI offers plugin management, configuration editing, dashboards,
accessory control, logs, backup, and child bridge controls; exposure of this
administrative surface merits tight access policy.

NixOS's [Homebridge module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/home-automation/homebridge.nix)
stores plugin downloads in a writable `node_modules` tree and gives the
service account passwordless service restart and host shutdown commands for
UI functions. It also grants a broad capability set. This is a source-code
observation, not a demonstrated exploit. Treat UI login as a privileged
administrative boundary, review installed plugins, and avoid publishing the
UI to the Internet. A site-specific service override should be evaluated
against UI behavior before dropping capabilities or sudo commands.

For a hostname under an existing public domain that only works on the LAN,
use local DNS resolution to a private reverse-proxy address and keep ingress
restricted by host firewall and gateway policy. [Let's Encrypt DNS-01](https://letsencrypt.org/docs/challenge-types/)
can issue a trusted certificate without exposing HTTP validation on the Pi.
The deployed Pi uses DNS-01 to obtain its own apex and wildcard certificate.
Cloudflare [Origin CA certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
are intended for Cloudflare-to-origin traffic and are not normally trusted by
browsers connecting directly to a LAN origin. Avoid a Cloudflare public proxy
record or tunnel for a service required to be LAN-only. Do not assume that a
public DNS-only private-address record alone enforces LAN access; the host
and gateway rules remain the control.

The Pi now serves the UI through its own nginx listener on the Servers address.
The Homebridge UI remains bound to loopback. The Pi firewall permits HTTPS only
from the Trusted subnet; nginx repeats that source check. The DNS-only exact A
record selects the Pi ahead of the desktop's wildcard record. A normal request
returned HTTP 200 with a trusted certificate, a WebSocket upgrade returned 101,
and a request sourced from the Servers subnet received 403. The desktop's former
SSH forward and nginx site were removed, so turning off the desktop no longer
removes this HTTPS path. The desktop's weekly encrypted backup remains optional.
A clean Pi reboot restored Homebridge, nginx, the source-scoped nftables rule,
the sealed DNS credential, and the certificate service without intervention.

The [official Homebridge container](https://github.com/homebridge/docker-homebridge)
supports ARM64, includes ffmpeg, requires host networking, and keeps configuration
and plugins in its persistent `/homebridge` volume. It is a practical fallback
when plugins assume a conventional Ubuntu environment. Declare it through NixOS
OCI containers and pin an image digest. That pin does not pin plugins installed
into the mutable volume. Coordinate its Avahi configuration with the host rather
than starting competing discovery daemons. Containers share the host kernel;
their cost is runtime processes and additional disk contents, not a separate VM.
No native-versus-container memory benchmark was run.

## Arlo cameras

First check native Apple Home compatibility for the exact camera and base
station combination. Arlo's
[integration guidance](https://www.arlo.com/en_gb/support/faq/connectivity-and-integrations/when-adding-my-base-station-to-homekit-what-should-i-do-if-i-receive-an-error-message-stating-that-my-arlo-base-station-is-an-uncertified-accessory)
requires a compatible camera and SmartHub or base station. A native connection
can remove the Pi from the camera path entirely. Do not equate Apple Home
compatibility with HomeKit Secure Video recording support.

If camera bridging is necessary, evaluate Scrypted before adopting a Homebridge
Arlo plugin. This is an architectural recommendation, not a measured comparison.
[Scrypted's camera documentation](https://docs.scrypted.app/add-camera.html)
lists an Arlo integration, and its
[HomeKit integration](https://docs.scrypted.app/homekit)
supports streaming and HomeKit Secure Video. The latter requires an Apple TV
or HomePod. The
[Arlo plugin README](https://github.com/scryptedapp/arlo)
documents Arlo Cloud access, SMS/email 2FA, optional IMAP retrieval of codes,
stream conflicts, rebroadcasting, possible transcoding, and restrictions on
prebuffering battery cameras. This remains a cloud-dependent integration.
Validate login renewal and motion events as well as a live stream. Review any
trade-off with existing Arlo recording before changing camera settings.

By comparison, the inspected
[Homebridge Arlo README](https://github.com/homebridge-plugins/homebridge-arlo)
warns that an Arlo account allows one concurrent login and recommends a
separate account for Homebridge. That does not prove the Homebridge plugin
fails, but its existence is insufficient evidence for unattended reliability.
Test the exact camera model, authentication flow, stream behavior, and current
release with a dedicated account before considering this integration complete.

For a few camera bridges, the Pi remains a candidate only after measuring the
actual stream processing. Prefer compatible streams that avoid video
transcoding. As a planning preference, 4 GB provides more room for Homebridge
plus Scrypted than a 1–2 GB board; no camera count or RAM guarantee is established.
Scrypted's [system requirements](https://docs.scrypted.app/server-hardware.html)
allow low-power Pi 4 use for basic operation, require wired networking, and
separately discourage Pi 4 for NVR workloads. They also classify Arlo cloud
cameras as unsupported for Scrypted NVR. HomeKit bridging and running a local
continuous-recording NVR are different workloads.

My recommendation is native Arlo-to-Apple-Home integration if sufficient,
otherwise a small Scrypted bridge alongside Homebridge or on an existing
always-on Linux server. Declare Scrypted's official container through NixOS if
choosing that route, with persistent state, explicit ports, and a pinned image.
Upstream's documented Linux Docker host is Ubuntu, so NixOS integration needs
its own runtime verification. Move sustained transcoding to a suitable existing
machine if the Pi cannot meet latency and resource targets. Leave continuous
recording and media analysis off the tiny appliance.

## Deployment and resource policy

[Deploy-rs](https://github.com/serokell/deploy-rs) supports NixOS activation,
remote builds, and automatic rollback when confirmation fails. Add a Pi node
using `deploy-rs.lib.aarch64-linux.activate.nixos` and keep confirmation rollback
enabled. Unlike the existing desktop node, prefer `remoteBuild = false` for the
Pi and configure an off-device builder. This flag alone does not create one.

Use an ARM Linux machine or an ARM Linux VM on Apple Silicon for uncached
`aarch64-linux` derivations. A Darwin host alone cannot build Linux outputs.
An x86 Linux builder needs configured ARM emulation or cross compilation;
cross builds can miss native cache reuse and have package-specific failures.
Nix's [distributed build documentation](https://nix.dev/manual/nix/latest/advanced-topics/distributed-builds.html)
describes builder platform requirements. Prefer native ARM Linux building and
signed substitutes. Check Pi-specific kernel cache coverage before an update.
If no off-device builder exists, a cached local rebuild can work, but avoid
unplanned kernel or npm compilation on a low-memory Pi.

Suggested appliance policy, based on engineering judgment rather than measured
Homebridge capacity:

- Keep it headless. Select only base networking, SSH, time synchronization,
  secrets, boot support, and the required service. Avoid workstation modules,
  a graphical environment, and media-service profiles.
- Use Ethernet and a DHCP reservation. Keep HomeKit discovery and device access
  on a working local network. Do not put Homebridge in a download VPN namespace.
  VLAN separation needs both multicast discovery and allowed accessory traffic.
- Permit UDP 5353 and the configured HomeKit TCP ports on the intended interface.
  Restrict UI port 8581 to administration clients or an SSH tunnel. Pin child
  bridge ports explicitly; the native module's firewall convenience does not
  cover arbitrary child ports. Homebridge documents process isolation through
  [child bridges](https://github.com/homebridge/homebridge/wiki/Child-Bridges).
- Add plugins only for identified device models and use native Apple Home
  integration when it already meets the need. A UniFi client list identifies
  network clients, not the vendor APIs, accounts, bridges, or HomeKit support
  required to select a correct Homebridge plugin. The Homebridge
  [verified-plugin criteria](https://github.com/homebridge/homebridge/wiki/verified-Plugins)
  provide a useful first filter, but exact device compatibility and credentials
  still need device-level verification. Install and test one plugin at a time.
- Use child bridges selectively for plugins that are slow or unreliable.
  [Homebridge's child bridge guide](https://github.com/homebridge/homebridge/wiki/Child-Bridges)
  says they isolate plugin processes and allow separate restart, while each
  adds another Node.js process and typically about 20–30 MB RAM. Give each
  child bridge a stable unique HAP port and allow that port where Home hubs
  connect; avoid one child process per trivial accessory on a 2 GB board.
- Treat 2 GB RAM as a reasonable starting point for ordinary accessories, not
  a requirement or capacity guarantee. A 1 GB board may work with few light
  plugins. Measure the complete service process group after all devices are
  connected before imposing memory limits. Child bridges add processes.
- Prefer SSD storage for persistent state when available. A high-endurance SD
  card is a reasonable modest-installation compromise. A 32–64 GB card is a
  planning range, not a measured closure requirement. Budget for two closures
  during updates, retained generations, plugins, and backups.
- Bound journal storage, use scheduled garbage collection with a recovery
  window, and retain several known-good boot generations. Small zram swap can
  absorb bursts; it does not increase sustained capacity. Avoid routine SD swap.
- Use an adequate board-specific power supply and cooling. Verify restart
  after power loss and temperature under the actual workload. Add a UPS only
  when outage behavior warrants its cost.
- Back up configuration, pairing identity, accessory state, and plugin versions
  off-device. Prefer Homebridge's
  [backup and restore workflow](https://github.com/homebridge/homebridge/wiki/Backup-and-Restore)
  or a service-stopped consistent state backup. Encrypt backups containing
  credentials. Restoring pairing state helps avoid re-enrollment.
- Update deliberately and test a real accessory from Apple Home afterward.
  Deploy-rs SSH confirmation does not prove discovery, plugin health, or the
  next boot. System rollback does not undo application state migrations.

## Implication for this repository

Local observations:

- [The deployment configuration](../../hosts/shared/local/flake/deploy.nix) already defines deploy-rs
  for the desktop, with `remoteBuild = true`. Do not copy that build placement
  policy to a tiny appliance.
- [The desktop homelab integration](../../hosts/nixos/desktop/local/homelab/default.nix)
  imports optional modules into a host. The
  [nix-homelab README](../../nix-homelab/README.md) explicitly assigns hardware,
  disks, secrets, and backup destinations to the consuming host.
- The inspected service catalog has no Homebridge module. The desktop profile
  changes media-job priorities, and the media profile enables a media stack.
  Neither provides a Homebridge resource policy. Importing the library enables
  no applications by itself, so the ownership recommendation is not a claim
  that the import automatically runs a large stack.

Start with a general-purpose target such as `hosts/nixos/raspberry-pi/`, matching this repository's target and
`local/` module conventions. Promote reusable behavior to
`modules/nixos/services/homebridge.nix` when appropriate. If the service becomes
part of nix-homelab's supported scope, move its reusable implementation there
with ARM checks, state inventory, recovery documentation, and plugin tests.
The Pi stays a host in this repository either way.

## UniFi network placement

Use a server VLAN with a DHCP reservation tied to the Pi's Ethernet MAC.
The reservation follows the client; native VLAN and tagged VLAN policy belong
to each switch port. When moving the Pi, configure its new port for the same
server VLAN and retire the old port's device-specific name and policy as needed.
An ordinary endpoint needs an access port with tagged VLANs blocked.

[UniFi's mDNS proxy](https://help.ui.com/hc/en-us/articles/12648701398807-UniFi-Gateway-Multicast-DNS-mDNS-Proxy)
can share discovery across selected VLANs in Custom mode. Include the server
and trusted controller networks; include IoT where a plugin needs discovery.
Keep the services already selected for those networks and add the HomeKit HAP
service `_hap._tcp.local` for the Pi. If the existing scope shares all services,
select the services needed by the existing devices before narrowing that scope.
Discovery does not grant application reachability. Separately permit the
configured HAP TCP ports from controllers and home hubs, administration access
from management clients, and each plugin's required accessory traffic.
[UniFi firewall policies](https://help.ui.com/hc/en-us/articles/115003173168-Zone-Based-Firewalls-in-UniFi)
can scope those permissions by address, port, and protocol. A gateway ping does
not establish client access or HomeKit functionality.

Verify the new lease after a VLAN change before diagnosing SSH authentication.
Controller client tables can retain an old address temporarily. A successful
TCP connection and SSH handshake establish reachability; a key rejection does
not identify the board or prove which login accounts exist.

## Validation and limits

The implemented host was evaluated and built on the desktop, then booted on a
Raspberry Pi 4 Model B. Repeated boots succeeded with SSH, networkd, Avahi, and
Homebridge active and no failed systemd units. Ethernet DHCP, the reserved
address, key-based SSH from two administration hosts, the Homebridge TCP port,
the UI through an SSH tunnel, and local `_hap._tcp` advertisement were verified.
Deploy-rs dry activation and full activation both succeeded; the Pi rebooted
cleanly after deployment. At the measured idle point, about 1.4 GiB of 1.8
GiB RAM was available and zram swap was unused. This is an idle observation,
not a plugin or camera capacity test.

The desktop also runs a weekly backup timer. A manual run produced an encrypted,
compressed archive of Homebridge configuration, pairing state, UI authentication,
and plugin files. Decrypting and listing that archive succeeded. Backup retention
and a full destructive restore remain untested.

The initial boot appears to have stopped before NixOS: the root filesystem had
no first-boot state, and the extlinux configuration was on a GPT partition
without a bootable attribute. The [U-Boot bootflow
documentation](https://docs.u-boot.org/en/stable/usage/cmd/bootflow.html) and
the [vendor Pi 4 disk example](https://github.com/nvmd/nixos-raspberrypi-demo/blob/main/disko-usb-btrfs.nix)
support marking the partition that contains extlinux as bootable. The corrected
[disk layout](../../hosts/nixos/raspberry-pi/local/disko.nix) sets attribute bit 2; the
Pi booted after that change.

HomeKit pairing, accessory traffic, and Arlo camera plugins remain untested.
The gateway's Custom mDNS scope now includes Servers, Trusted, and IoT.
The Homebridge `_hap._tcp` advertisement was observed from a Trusted LAN
client, confirming cross-VLAN discovery at the DNS-SD layer. Pairing and
accessory traffic still need an Apple Home test.
The performance and
reliability of a camera workload cannot be inferred from the idle measurement.
Existing unrelated staged and unstaged work was preserved.
