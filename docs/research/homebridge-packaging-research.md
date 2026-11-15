# Homebridge package ownership and Node.js version

Reviewed: 2026-09-28. Scope: the Raspberry Pi Homebridge service, root Nixpkgs
revision `44a91898084f46797b5fac650c7e8c9ac38c43d4`, and the Pi vendor
Nixpkgs input. The question is whether a personal Homebridge package would
produce a newer or more complete build than upstream Nixpkgs.

The Pi now uses the root Nixpkgs revision for its NixOS system as well as
Homebridge. The vendor-pin comparisons below record the prior configuration;
see [the Pi Nixpkgs review](raspberry-pi-nixpkgs-unification-research.md) for
the shared-pin decision.

Update, 2026-10-01: the shared root pin is now
`c59305bab2065cfecc4944690d9eedbb56f3a9fa` on `nixos-unstable`.
Both desktop and Pi evaluate to NixOS `26.11.20261001.c59305b`; the Pi
selects Homebridge 2.4.0 and UI 5.29.0. The version comparisons below describe
the September 28 review, before this pin update. No personal Homebridge package
or second NixOS branch was needed.

## Answer

Keep the upstream Homebridge and UI recipes. The root pin contains Homebridge
2.3.1 and Homebridge UI 5.29.0. The latest stable releases are
[Homebridge 2.4.0](https://github.com/homebridge/homebridge/releases/tag/v2.4.0)
and [UI 5.29.0](https://github.com/homebridge/homebridge-config-ui-x/releases/tag/v5.29.0).
Current Nixpkgs already packages both. Its recipes fetch tagged upstream source
and use `buildNpmPackage` with fixed npm dependency hashes. The UI recipe builds
its server and web UI. Update the root pin or borrow the newer upstream core
recipe after testing; maintaining a personal copy is not needed for currency.

Node 24 is the right production target today. The [Node.js release schedule](https://github.com/nodejs/Release#release-schedule)
lists 24 as Active LTS and 26 as Current until its planned LTS start on
2026-10-28. Both [Homebridge 2.4.0](https://github.com/homebridge/homebridge/blob/v2.4.0/package.json)
and [UI 5.29.0](https://github.com/homebridge/homebridge-config-ui-x/blob/v5.29.0/package.json)
permit Node 26 in their `engines`, but the [Homebridge runtime guide](https://github.com/homebridge/homebridge/wiki/How-To-Update-Node.js)
describes support for Node 26 from October 2026. `engines` compatibility alone
does not establish that this service and its plugins are ready to move before
then.

## Findings and sources

- The root pinned [Homebridge recipe](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/ho/homebridge/package.nix)
  is version 2.3.1. The newer [upstream Nixpkgs recipe](https://github.com/NixOS/nixpkgs/blob/3c1ed264fa49fa2abfe248993ee2ec4c38747d91/pkgs/by-name/ho/homebridge/package.nix)
  is 2.4.0 and uses `buildNpmPackage`, `fetchFromGitHub`, and a fixed
  `npmDepsHash`. The pinned [UI recipe](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/ho/homebridge-config-ui-x/package.nix)
  is 5.29.0. It explicitly selects `nodejs_24`, separately pins npm dependencies
  for the `ui` directory, and invokes the upstream build. The
  [upstream scripts](https://github.com/homebridge/homebridge-config-ui-x/blob/v5.29.0/package.json)
  build the TypeScript server and Angular UI.
- Neither pinned recipe enables the upstream test suite. The UI recipe enables
  an installed command version check, while the core recipe has no explicit
  check phase. Adding focused build or runtime checks upstream would improve
  confidence, especially for ARM64 and a future Node major upgrade. The
  [core recipe](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/ho/homebridge/package.nix)
  and [UI recipe](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/ho/homebridge-config-ui-x/package.nix)
  show their declared checks.
- The UI's dependency tree includes
  [`@homebridge/node-pty-prebuilt-multiarch`](https://github.com/homebridge/homebridge-config-ui-x/blob/v5.29.0/package.json).
  The [Nixpkgs UI recipe](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/ho/homebridge-config-ui-x/package.nix)
  comments on using its prebuilt variant and has a Darwin build limitation.
  Inspection of the local UI output found bundled `.node` files for several
  Linux architectures and Node ABIs. Thus the UI application is built from
  source, but every native dependency is not necessarily compiled from source.
  This is a possible upstream packaging improvement, not a reason by itself to
  fork the complete Homebridge package for the Linux Pi.
- The Pi host [selects the root Nixpkgs packages](../../hosts/nixos/raspberry-pi/local/homebridge/default.nix)
  inside the vendor-pinned NixOS system. The root input evaluates to Homebridge
  2.3.1 and UI 5.29.0. The vendor input alone evaluates to 2.0.2 and 5.22.0.
  This package selection already closes the relevant version gap without
  replacing the Pi's kernel and boot-support pin.
- The built package launchers in the local Nix store call Node 24.20.0. The
  [NixOS service module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/services/home-automation/homebridge.nix)
  also adds its host's `pkgs.nodejs` to the service PATH, which evaluates to
  24.18.0 on the vendor pin. This means the pinned launchers and commands run
  by the service PATH, including npm plugin installs, can use different Node
  24 patch releases. Aligning that PATH with the root package input is a small
  host integration improvement to assess when next changing the service.
- Nixpkgs has an existing
  [Homebridge NixOS module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/services/home-automation/homebridge.nix)
  that wires the UI, core package, writable plugin directory, and systemd
  service together. The [Pi configuration](../../hosts/nixos/raspberry-pi/local/homebridge/default.nix)
  uses that module and already tightens local settings. A package fork would
  leave this service wiring and mutable plugin management unchanged.

## Validation and limits

I evaluated versions from both pinned Nixpkgs inputs for `aarch64-linux` and
the resulting Pi service configuration, then inspected the package recipes and
built launchers in the local Nix store. The package launchers and UI output were
already present; this review did not rebuild either package, activate a new
generation, test Node 26, or run plugin and HomeKit behavior. The existing
[Pi deployment note](raspberry-pi-homebridge-research.md) records a prior build,
activation, and reboot test of the upstream packages. I did not repeat those
runtime checks.

## Implication for this repository

Retain the upstream packages. If Homebridge 2.4.0 is wanted now, first update
the root Nixpkgs pin or use the newer upstream core recipe through a narrow
override, then verify an ARM64 build and runtime. Keep Node 24 for production
until Node 26 reaches LTS and the selected plugins have been checked. At that
point, test core, UI, and service plugin tooling on the same Node version. Create
a personal package only if a specific upstream packaging defect blocks that
route and cannot be fixed with a small override or upstream contribution.
