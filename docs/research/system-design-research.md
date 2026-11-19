# Where can the workstation configuration own each decision once?

Reviewed 2026-11-17 against the working tree based on `75b5bb62e1dd`.
The Nixpkgs pin is `b3cff76391a4867236cc135b69a928d873b9f6d0`.
The review covers root-owned configuration and representative NixOS,
Home Manager and cross-platform packaging interfaces.

## Answer

Clear the desktop evaluation cycle first. Then consolidate wallpaper fetcher
definitions, give Aurral's listener port one owner, and give each Rust runtime
package one packaging policy entry. Extract the two shared libvirt operations
before considering a larger file split. Rank changes by how many coordinated
edits they remove and how independently the result can be evaluated.

## Findings and sources

### 1. Keep the Zen launcher local to its consumers

Desktop evaluation fails with infinite recursion through Home Manager's
`lib` option, the Zen package and Zen profiles. The launcher module exports
a package-dependent launcher and a diagnostic link farm through `config.lib`.
A repository search found no reads of those exports. An in-memory module
override omitting both exports evaluated the integrated home with the launcher
and slice still present. Keep the launcher as a local binding used by the
desktop entries and package list. If the diagnostic output has a downstream
consumer, give it a dedicated output or typed option that avoids the cycle.
[Launcher module](../../homes/desktop/local/browsers/session.nix#L48),
[pinned Nixpkgs module evaluator](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/lib/modules.nix),
[Nix module system](https://nix.dev/tutorials/module-system/deep-dive.html).

### 2. Generate wallpaper units from ordered source records

The wallpaper module declares three near-identical service/timer pairs. The
same source identifiers recur in command definitions and in the seed list.
Use a private ordered list with each connection key, stable unit name, label
and fetch command. Generate the packages, units and seed list from it. Keep
provider-specific options and command construction visible. Preserve Commons,
Hubble and Webb seeding order, the shared service restrictions and the timers.
Install all three units in rotate mode so runtime preferences can enable a
source even when its declarative default is off. Reuse connection labels from
the existing catalog where they match, and compare source keys against that
catalog when evaluating the change. Keep systemd details with the module.
[Wallpaper units](../../modules/home/desktop/wallpaper.nix#L636),
[seed loop](../../modules/home/desktop/wallpaper.nix#L246),
[catalog](../../modules/home/desktop/wallpaper-catalog.json),
[systemd timer target selection](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html).

A local generator fits the current closed set. If independent modules later
need to contribute named entries, `attrsOf (submodule ...)` supports typed
fields and overrides by key. Keep sequence explicit when order matters.
[Nix nested submodules](https://nix.dev/tutorials/module-system/deep-dive.html#nested-submodules),
[pinned option types](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/lib/types.nix).

### 3. Resolve service endpoints from their owners

Aurral's port appears in the application environment, both bridge ends,
bootstrap callers, a health probe, a firewall assertion and the proxy. Give
it one typed port in the existing host-local Aurral options. Derive the
backend URL and consume it in callers. Preserve loopback binding and the
distinct sides of the VPN bridge. The proxy already reads Seerr and the Arr
services' own port settings. The dashboard and HTTPS monitoring already derive
from site declarations, so extend that composition when adding sites.
[Aurral listeners](../../hosts/nixos/desktop/local/homelab/music/aurral.nix#L122),
[Aurral options](../../hosts/nixos/desktop/local/homelab/music/quality-policy.nix),
[HTTPS sites](../../hosts/nixos/desktop/local/homelab/https.nix#L135),
[dashboard derivation](../../nix-homelab/modules/operations/dashboard.nix).

The pinned Jellyfin module documents that the application UI can change its
listener. Treat the repeated default port as a host integration expectation
until listener ownership is established. Verify the actual listener at
runtime. [Pinned Jellyfin module](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/nixos/modules/services/misc/jellyfin.nix),
[Jellyfin integration](../../hosts/nixos/desktop/local/homelab/media.nix#L292).

### 4. Consolidate Rust packaging policy by package

The runtime registry uses separate lists or maps for Linux eligibility, native
dependencies, main programs and output names. It exports 46 packages for
48 Cargo workspace members. The other two are internal libraries. All 48
members inherit the workspace version, and the Nix builder repeats that
version literally. The registry already derives its source fileset from Cargo
membership. CI already derives package checks and platform exclusions from
registry outputs. [Runtime registry](../../flake/runtime-packages.nix),
[Cargo manifest](../../Cargo.toml),
[Rust checks](../../flake/dev/rust-checks.nix),
[Cargo workspace inheritance](https://doc.rust-lang.org/cargo/reference/workspaces.html#the-package-table).

Use a Nix table keyed by existing output names, with crate name and optional
platform, library and main-program metadata per package. Derive version from
workspace metadata and validate crate names against Cargo membership.
Nix package references and native dependencies fit directly in this table.
Cargo's `package.metadata` is another option if central edits become a
bottleneck, but it would need validation and a mapping for Nix dependencies.
Measure build churn separately before accepting the complexity of narrower
source views. The shared workspace source and lockfile still couple builds.
[Cargo metadata](https://doc.rust-lang.org/cargo/reference/manifest.html#the-metadata-table),
[prior Rust design research](rust-quality-design-research.md).

### 5. Extract operations already shared by the libvirt modules

The 1,026-line workstation module and 865-line Windows module both write a
JSON policy and executable wrapper for the same Rust binary. Both also run
`virt-xml-validate` with artifact-specific schema names. Share the launcher
and XML validation behind a feature-local helper. Preserve command and
output names, argument forwarding and schema selection. If navigation still
needs improvement, organize the remaining code around network and storage
definitions, Windows installer media, and runtime reconciliation. Preserve
selectors, typed options, assertions, the Windows recipe fingerprint and
runtime mutation gates. The framework discovers visible Nix files, so place
private helpers outside the discovered set and import them explicitly.
[Workstation module](../../modules/nixos/virtualisation/libvirt.nix),
[Windows module](../../modules/nixos/virtualisation/windows-vm.nix),
[libvirt XML validation](https://libvirt.org/manpages/virt-xml-validate.html),
[framework selectors](../../nix-config-framework/README.md#layout-and-selectors).

### Choose an interface based on who supplies the values

Use a private record or native data file when one feature owns the whole
collection. When independent modules contribute named entries, use typed
submodules and put overridable defaults on individual fields. A default
on an entire collection can disappear when a caller defines one key.
Use a format-backed `settings` subtree for application-owned settings and
declare types for the fields the integration relies on. A freeform subtree
can accept misspellings that are valid in the underlying file format.
[Pinned merge implementation](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/lib/modules.nix#L1300-L1369),
[NixOS settings guidance](https://raw.githubusercontent.com/NixOS/nixpkgs/b3cff76391a4867236cc135b69a928d873b9f6d0/nixos/doc/manual/development/settings-options.section.md),
[NixOS RFC 42](https://github.com/NixOS/rfcs/blob/45b76f20add8d7e0e1d0bc0eed9357b067c899a6/rfcs/0042-config-option.md).

## Validation and limits

- On x86_64 Linux, the full desktop derivation evaluation and an integrated
  Home Manager projection reproduced the Zen recursion. The in-memory override
  evaluated the integrated home projection, including its launcher, Zen slice
  and wallpaper mode. Full desktop derivation evaluation with the override
  exceeded a 75-second limit, so full evaluation remains unverified.
- Isolated Home Manager evaluation resolved three rotate-mode fetcher service
  and timer pairs, each with a five-minute service timeout and daily timer.
  The seed timeout resolved to 31 minutes. Desktop NixOS projections resolved
  both homelab proxy routes and confirmed that libvirt and the Windows VM
  were enabled.
- Runtime registry evaluation selected 46 outputs for x86_64 Linux and 20
  for aarch64 Darwin using existing platform metadata. A module evaluation
  probe verified that a normal port definition overrides `mkDefault` within
  a named submodule while merging a sibling setting.
- An independent evaluation of the pinned Nixpkgs library confirmed that a
  partial definition replaced a collection-wide default and preserved an
  unrelated per-key default. A closed submodule rejected an undeclared key,
  while the format-backed freeform subtree accepted it.
- This was a research pass. No builds, runtime tests or activation ran.

## Implication for this repository

Use full desktop derivation evaluation to verify the Zen correction. In the
follow-up refactors compare the evaluated unit definitions and seed order,
proxy and listener settings, package names and platform availability, and
libvirt wrapper arguments and generated XML. Use existing checks and targeted
before/after evaluation. Keep physical deployment facts, published names and
safety limits explicit at their owners. Use native application options for
settings they already model and format generators for configuration the
repository owns. [Contributor guide](../../CONTRIBUTING.md),
[generated configuration research](nix-generated-config-schema-research.md).
