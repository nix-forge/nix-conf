# Raspberry Pi Nixpkgs and board support

Reviewed: 2026-10-01. Scope: Raspberry Pi 4 Model B, the repository's locked
`nixos-unstable` Nixpkgs and `nvmd/nixos-raspberrypi` revision
`7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10`.

On 2026-10-01, the shared root Nixpkgs pin was updated again to
`c59305bab2065cfecc4944690d9eedbb56f3a9fa`. The desktop and Pi now
evaluate to NixOS `26.11.20261001.c59305b`, and the Pi selects Homebridge
2.4.0 with UI 5.29.0. The Pi kernel output remains
`/nix/store/w4a7jcdzppyg59wg8jpj50m4dk12hzzi-linux_rpi-bcm2711-6.18.34-unstable_20260604`;
the vendor Nixpkgs pin was not updated. The earlier root revision and
Homebridge version below record the initial unification test.
The Pi's `system.stateVersion` remains `26.05` to preserve stateful defaults;
it does not choose the NixOS package branch. The new generation was activated
on 2026-10-01, and the running system reported 26.11 immediately afterward.

The deployment now builds the ARM system on the desktop, which already has an
active AArch64 binfmt handler. The deployment script explicitly copies the
kernel from the vendor's signed cache before building. If that output is
missing, the command fails instead of compiling a kernel under emulation.
Deploy-rs transfers completed outputs to the Pi over SSH; the Pi only
activates them. This keeps the Pi's cache trust limited to the official and
board vendor keys. [NixOS binfmt options](https://nixos.org/manual/nixos/unstable/options#opt-boot.binfmt.emulatedSystems),
[Nix binary cache guide](https://nix.dev/guides/recipes/add-binary-cache.html),
[deployment configuration](../../hosts/shared/local/flake/deploy.nix).

Evaluating the complete 26.11 system exposed two defaults that expect
`buildDTBs` and `target` attributes on the kernel derivation. The vendor's
cached kernel predates those attributes. The Pi configuration now disables the
upstream device-tree build because its U-Boot path installs matching device
trees from vendor firmware, and sets the boot kernel filename to the existing
`Image`. This preserves the cached kernel derivation and lets the complete
system toplevel evaluate.

## Answer

Use the root Nixpkgs input for the Pi's NixOS system and ordinary packages.
Keep the board-support project's tested Nixpkgs pin for its Pi kernel and
firmware bundle. That is still a second Nixpkgs input, but it does not select
the Pi's NixOS version or Homebridge version. It avoids recompiling the kernel
on the desktop: the exact kernel, modules, and firmware outputs selected from
the vendor pin are present in the signed vendor cache. The same kernel built
against the root pin is absent from that cache. This is the least disruptive
route for the existing U-Boot, extlinux, and `/boot/firmware` installation,
subject to a full system build and an actual Pi boot test.
[Board-support usage](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/README.md),
[helper implementation](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/lib/default.nix),
[existing disk layout](../../hosts/nixos/raspberry-pi/local/disko.nix).

The more standard upstream route for a Pi 4 is the generic AArch64 NixOS
image plus the `nixos-hardware` Pi 4 profile. That profile builds its kernel
and firmware with the caller's Nixpkgs and now provides firmware partition
activation for installed systems. It has different module options and boot
integration, so changing to it on an already deployed headless Pi is a separate
boot migration requiring recovery media and runtime validation. The desire for
one package collection alone does not justify that migration.
[NixOS Pi 4 guidance](https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_4),
[nixos-hardware Raspberry Pi documentation](https://github.com/NixOS/nixos-hardware/blob/master/raspberry-pi/README.md),
[Pi 4 profile](https://github.com/NixOS/nixos-hardware/blob/master/raspberry-pi/4/default.nix).

## Findings and sources

Before this change, the root flake tracked `nixos-unstable`, locked to Nixpkgs
`4975466d324710c576dc11ad614684e6bd8cad8e`. The Pi system used
`inputs.nixos-raspberrypi.inputs.nixpkgs.lib.nixosSystem`, and the vendor input
was locked to a Nixpkgs revision on `nixos-26.05`. The patch under review
constructs the Pi with `inputs.nixpkgs.lib.nixosSystem` while retaining the
vendor's Nixpkgs pin for its own package outputs. These observations come from
[the flake](../../flake.nix), [Pi composition](../../hosts/shared/local/flake/raspberry-pi.nix),
and [the lock file](../../flake.lock). The vendor's August 2026 release notes
confirm that its default pin moved to `nixos-26.05`; they also explain that
configurations overriding its Nixpkgs input can use another version.
[Vendor release notes](https://github.com/nvmd/nixos-raspberrypi/releases/tag/v1.20260801.0).

The vendor's documented direct `nixpkgs.lib.nixosSystem` path requires passing
`nixos-raspberrypi` through `specialArgs` and importing `inject-overlays` plus
the selected board module. The current Pi configuration already does both;
its system constructor was what made the entire Pi system use the separate
Nixpkgs branch.
The vendor's installer uses `self.lib.nixosInstaller`, whose default Nixpkgs is
`self.inputs.nixpkgs`. The extended Pi 4 installer therefore still uses the
vendor's 26.05 pin. It is a recovery and provisioning output, separate from
the deployed Pi system. This follows directly
from [the vendor flake](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/flake.nix)
and [helper implementation](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/lib/default.nix).
[Vendor usage](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/README.md),
[Pi inventory](../../hosts/nixos/raspberry-pi/default.nix),
[Pi composition](../../hosts/shared/local/flake/raspberry-pi.nix).

The vendor pairs a downstream kernel with matching firmware and device trees.
Its latest published release as checked on 2026-10-01 is the pinned August 2026
release, which selects kernel `6.18.34`; the release notes say the bundle is
unchanged from July. "Latest" here means the vendor's selected bundle at that
revision, not the newest Linux kernel available anywhere.
[Vendor releases](https://github.com/nvmd/nixos-raspberrypi/releases/tag/v1.20260801.0).
Its [cache workflow](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/.github/workflows/cachix.yaml)
builds Pi 4 kernel and module outputs on an ARM runner. The cache is for
outputs produced by the vendor's locked Nixpkgs, as its
[README](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/README.md)
states. The Pi 4 module selects that vendor kernel with `lib.mkDefault`, so it
can be overridden if a later migration to the generic NixOS kernel is chosen.
[Pi 4 module](https://github.com/nvmd/nixos-raspberrypi/blob/7e39508bcf9c1da82cf11c1e22f74f9d9fd0fe10/modules/raspberry-pi-4.nix).

The Pi selects its Cachix URL and public signing key through the repository's
shared cache module with `nix.caches.raspberry-pi.enable = true`. The root flake
also lists them for the first build, when the new Pi settings have not yet been
activated. The vendor cache module is not imported; its additional
`trusted-substituters` entry is unnecessary when the cache is already in the
daemon's active `substituters` list. Nix verifies a store object's signature
against `trusted-public-keys` by default. A cache key trusts the provider to
sign any matching store path, not only kernel outputs, so keep this as an
explicit repository trust decision and retain signature checking.
[Pi cache selection](../../hosts/nixos/raspberry-pi/default.nix),
[shared cache module](../../modules/shared/cache.nix),
[Nix cache settings](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html),
[repository cache policy](nix-caches-research.md).

The upstream NixOS wiki lists the Pi 4 as supported on stable and unstable
AArch64 channels, and its generic SD image includes Pi 4 boot files. The
`nixos-hardware` Pi 4 profile selects a downstream kernel, device trees, and
initrd modules; its firmware module writes the required files to a running
system's `/boot/firmware` when explicitly enabled. These sources establish a
viable one-Nixpkgs alternative, but do not prove it can boot this particular
installed disk without a migration test.
[NixOS ARM support](https://wiki.nixos.org/wiki/NixOS_on_ARM),
[generic AArch64 image source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/sd-card/sd-image-aarch64.nix),
[nixos-hardware README](https://github.com/NixOS/nixos-hardware/blob/master/raspberry-pi/README.md).

## Validation and limits

The investigation read the local source and lock file and checked upstream
documentation and source on 2026-10-01. On the desktop, evaluation of the Pi
system and U-Boot installer derivations succeeded during the experiment that
used the root pin for every output. The Pi system evaluated to NixOS
`26.11.20260923.4975466`, with kernel
`6.18.34-unstable_20260604` and Homebridge `2.3.1`. The first evaluation
exposed an obsolete `services.journald.extraConfig` assignment; changing it to
`services.journald.settings.Journal` resolved that assertion. This was the
initial evaluation, before the later shared Nixpkgs update and full Pi build.

For the root-pinned vendor kernel derivation, the evaluated output paths had
store hashes `aafx4089pmhb5ylbba5lm28fnxifhca0` for the kernel,
`4d9asqwrw4h0s900g5vybiylsyllyzag` for modules, and
`py654gwqhm6kpxrlz2b6yhq2pldzbgmf` for development files. Direct
`<CACHE>/<HASH>.narinfo` requests on 2026-10-01 returned HTTP 404 for all
three hashes from the vendor, NixOS, and Nix Community caches. This is an
exact-path cache miss, even though the kernel version string matches the
vendor's bundle.

With the vendor pin restored for its package outputs, the evaluated Pi kernel
path hash is `w4a7jcdzppyg59wg8jpj50m4dk12hzzi`, matching the running Pi's
kernel path. Its modules hash is `kvb69f0kyvgy2q6365di6j8x83rkcrhi`, and
its firmware hash is `y07a54749q2aqdyh253h4wirl2mssrx3`. Direct narinfo
requests returned HTTP 200 for all three from the vendor cache and HTTP 404
for all three from the official NixOS cache. These initial requests checked
metadata availability. The later desktop build copied the exact kernel path
from the signed vendor cache, reused its compiled modules, and built the full
Pi closure without compiling the kernel. Uncached application packages and
system assembly ran under the desktop's AArch64 binfmt handler.

The desktop build, closure transfer, and deploy-rs dry activation passed on
2026-10-01. The first activation failed because five existing Nix-managed
Homebridge plugin links lacked the ownership ledger required by the current
reconciler. After checking each link's Nix store target and recording the five
links, Homebridge started. A second deploy-rs activation succeeded with
rollback confirmation. The running and boot profiles both point to NixOS
`26.11.20261001.c59305b`. Homebridge, Scrypted, nginx, and SSH were active;
systemd reported no failed units. The running Homebridge log reports
Homebridge 2.4.0 and UI 5.29.0. This confirms a live switch, but the Pi has not yet rebooted
into this generation, so its boot path remains unverified.

Later that day, the Pi stopped responding over the network. The desktop could
still reach the network gateway, but could not contact the Pi. The cause and
current runtime state have not yet been established; local power, Ethernet,
and client-address checks are needed before claiming a durable deployment.

## Implication for this repository

The configuration constructs the Pi system with
`inputs.nixpkgs.lib.nixosSystem`, retains the vendor input's own Nixpkgs pin
for its cached board outputs, and removes the Homebridge package override that
bridged the old system and root pins. The intended result is one NixOS branch
for desktop and Pi, with a second Nixpkgs pin confined to Pi boot packages and
the installer. Build the Pi closure on desktop and inspect the substitution
plan before activation. If it would compile the kernel, stop and revisit the
selected kernel output. Verify boot, Ethernet, SSH, and Homebridge after the
next reboot. Keep the Pi's `system.stateVersion` at `26.05`:
[NixOS documents](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion)
that it preserves compatibility defaults rather than selecting a Nixpkgs
branch.
