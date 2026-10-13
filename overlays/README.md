# Overrides and overlays

Temporary package and upstream module fixes live in [`temporary/`](temporary/default.nix).
Long-lived package selection and behavior live in [`permanent/`](permanent/).
[`default.nix`](default.nix) is a Nixpkgs overlay. Each target installs it through
`nixpkgsArgs.overlays`; attached Home Manager configurations share their host's
package set through `useGlobalPkgs`.
[`packages.nix`](packages.nix) owns platform conditions, package sources, and
the order in which fixes apply. It receives the incoming `prev` package set.
[`inputs.nix`](inputs.nix) applies module replacements to flake inputs before
configuration evaluation. Consumers keep their normal upstream module imports
when these replacements are retired.

Modules use ordinary package attributes:

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.prismlauncher ];
}
```

Retire each package fix in `packages.nix`. When an attribute needs no remaining fixes or
customizations, remove its override. The same module reference then resolves to
the upstream Nixpkgs package.
No custom module argument or package-selection helper is needed.

The overlay applies the selected package definitions throughout the configured
package set. The GtkSourceView repair remains confined to Virt Manager's dependency;
`pkgs.gtksourceview4` itself keeps its upstream definition. `pkgs.grimblast-region`
is a separate permanent variant, while `pkgs.grimblast` retains its normal behavior.

The overlay also owns the Determinate Nix package selection, its Darwin test
condition, the Darwin Actual repair, and the Linux Zen wrapper repair. The
Determinate modules configure the service and daemon settings.

## Which repository owns an override?

| Change | Location |
| --- | --- |
| Workaround for a broken upstream package used by this configuration | `overlays/temporary/<name>.nix` and `overlays/temporary/patches/` |
| Repair to an upstream NixOS, Home Manager, or flake module | `overlays/temporary/<name>.nix`, registered in `temporary/default.nix` |
| Lasting package selection or behavior shared by this configuration | `overlays/permanent/` |
| Independently useful package recipe or named variant | `pkgs/`, the separate nixpkgs-personal repository |
| Module settings, wrapper flags derived from options, feature selection | The owning module |

Classify a change by what it repairs. Rewriting upstream Nix source, replacing
an upstream module with `disabledModules`, or adapting option assignments inside
an upstream module is a temporary upstream fix even when implemented as a Nix module. Keep the
repair and its lifecycle record in `temporary/`; the owning configuration module
only selects the registered fix. Ordinary option values remain in their owning
module.

An `overrideAttrs` expression can be a package recipe. Its syntax does not decide
where it belongs. For example, `twemoji-color-font-optional` removes default
Fontconfig substitutions, `mplus-outline-fonts-compatible` avoids duplicate font
files, and `noctalia-personal` supplies selected UI behavior. Those reusable
variants belong in nixpkgs-personal. Keep repairs needed to build such a variant
with its recipe and validate them in that repository. Do not introduce a
dependency from nixpkgs-personal back into this configuration.

The permanent Determinate overlay selects the Nix implementation. Its Darwin
test workaround is a separate temporary fix. The Linux Sentry report-lock fix
passes a repaired Nix input directly to Determinate's NixOS module factory,
without changing the global package overlay or forcing `nix.package`. Its
[investigation and regression checks](../docs/sentry-crashpad-lock.md) describe
the source-aware skip and revision review needed for retirement.
Region-only Grimblast behavior is
a permanent override. Module-specific Git options and browser flags stay with
the module that owns those options.

Use `prev` for the incoming package in an overlay. Preserve the existing scope
when moving a local override. The GtkSourceView fix here still applies only to
Virt Manager's dependency. See the [Nixpkgs overlay and override documentation](https://nixos.org/manual/nixpkgs/unstable/index.html#chap-overlays).

Module fixes use the same registry and revision guard as package fixes. Their
`apply` function takes the upstream input and returns a module. The owning module
imports that result, as the Neovim module does for `stylix-nvf`. Construct its
registry with `{ inherit inputs lib; }` so import resolution does not depend on
`config._module.args.pkgs`. Module fixes stay outside the Nixpkgs overlay in `packages.nix`; they need no package version range.
When a fix replaces an exported upstream module, apply it in `inputs.nix` so
the consuming configuration does not need patch-specific imports.

## Temporary fix lifecycle

Every registered fix records its reason, upstream link, removal condition, input
path, and an explicitly reviewed input revision. Do not derive
`reviewedRevision` from the current lockfile at evaluation time. That would make
the check accept every update automatically.

The guard throws a review error when that input changes. This catches recipe
changes and backports even when a package keeps the same version. Track the
input that owns the affected source or recipe. A nested input can change
independently of its parent, so record that nested input path when needed.

When a release boundary is known, add `affectedVersions`:

```nix
affectedVersions = {
  from = "1.2.0";
  until = "1.4.0";
};
```

The lower bound is inclusive and the upper bound is exclusive. Both bounds must
be present, and the interval must be nonempty. The guard checks the incoming
package before applying an override that might change its version. A package
outside the interval fails evaluation with the fix name and removal condition.
The fix is never silently applied outside its declared range.

For a fix that should stop applying automatically after the affected versions,
declare `packageName` and an `appliesTo` predicate instead. The registry tests
the incoming package before applying the patch or its revision guard. Review
checks resolve `packageName` as a dotted attribute path below `pkgs` for the
same decision, so nested package sets such as `plugins.example` are supported.
If a registry has no package set, revision review remains conservative. Other
fixes keep their existing review behavior.

The `nh-darwin-home` fix applies through `nh` 4.4.2 and is skipped for newer
versions, including its own revision-review requirement. Upstream merged
[PR #758](https://github.com/nix-community/nh/pull/758) after the affected source;
the next release number is not yet announced. This cutoff assumes subsequent
releases include that correction. The inactive patch files can be deleted
during later maintenance; evaluation does not modify the checkout.

Nixpkgs now provides PrismLauncher 11.1.0, so the release override has been
retired. Its Darwin watch-test patch has a separate lifecycle. The other
workarounds have no confirmed fixed release recorded, so they use revision
review triggers.

The portal compiler override was retired at portal input
`e87ae7823e7bf0601385220c69b5a3b245123fc5`. Unmodified native builds passed on
[x86 Linux](https://github.com/nix-forge/nix-conf/actions/runs/38302691574/job/114989461417)
and [ARM Linux](https://github.com/nix-forge/nix-conf/actions/runs/38302691574/job/114989461739).
The native portal check now builds the selected upstream package with its GNU
compiler and keeps compiler compatibility covered without a temporary patch.

The Home Manager portal compatibility adapter was retired at
`6b88c12cc6d234de4888f5d21076fb11199d0844`. Its upstream Hyprland module now
checks `lib.functionArgs portalPackage.override` before passing the `hyprland`
argument, preserving the selected upstream portal without an adapter. The normal
native configuration and upstream portal checks cover the consuming graph.

These triggers are conservative. An input change means review is required; it
does not prove the bug is fixed. Keeping the revision guard alongside a version
range also catches packaging changes within that range. A merged PR or closed
issue is evidence to investigate, not proof that the pinned source includes a
working fix. Record the specific issue or PR URL when one is established.

## Add, check, and retire a fix

The Stylix nvf target was reviewed at
`2856c4c6a845b9bec98828ef197abe176e4806bb`; its source blob is unchanged.
The [paired module proof](https://github.com/nix-forge/nix-conf/actions/runs/38314456594/job/115027658395)
checks the actual enabled `nvf` target with current Home Manager and nvf modules.
Upstream emits the deprecated lualine theme warning; the repaired module has no
warnings. Both preserve the canonical `base16` theme and satisfy their assertions.

The Zen wrapper was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. Its only recipe change adds a
runtime library; the copy command, following mode update and Coreutils recipe
remain unchanged. The [native wrapper proof](https://github.com/nix-forge/nix-conf/actions/runs/38314456594/job/115027658416)
uses inert fixture binaries with the actual selected wrapper, verifying copied
payload bytes and modes, data, symlinks and launcher execution. The ordinary
Firefox wrapper retains its identical derivation. This supports retaining the
narrow repair; retirement on the native builder's store mount remains unverified.

The Swift Clang importer fix was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. Its combined compiler recipe,
driver recipe, compiler recipe, source manifest and hardening helper remain
identical to the previous reviewed source blobs. The
[native macOS proof](https://github.com/nix-forge/nix-conf/actions/runs/38312707376/job/115022124354)
selects the configuration's actual `swiftPackages.swift` 6.2.4 compiler.
Unmodified typechecking reports both missing fortify and strong stack protection;
the repaired importer receives both flags and passes typechecking, linking and
the native runtime probe. This justifies retaining the fix at the reviewed pin,
while the guard still rejects later input changes.

The AudioMuse-AI loopback manifest fix was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. The selected upstream plugin is
version 10, so the earlier release override automatically remains inactive.
The upstream v10 manifest still grants HTTP access to every host. The
[Linux-hosted WASI build and manifest check](https://github.com/nix-forge/nix-conf/actions/runs/38318398666/job/115040557695)
compiles the actual selected plugin and verifies that its packed manifest matches
the repaired source. Only `permissions.http.requiredHosts` changes to
`127.0.0.1`; every other manifest field and source file remains unchanged.
This validates packaging and permission scope, not a running Navidrome deployment.

The GtkSourceView, Hypridle and nix-output-monitor fixes were reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. Their upstream package recipes
and fixed source selections remain unchanged; nix-output-monitor's generated
package definition is also identical.

- The [GtkSourceView Linux build](https://github.com/nix-forge/nix-conf/actions/runs/38318398666/job/115040557870)
  retains the scoped Xvfb `-noreset` repair and passes all 23 native Meson tests.
- The [Hypridle Linux proof](https://github.com/nix-forge/nix-conf/actions/runs/38318398666/job/115040557887)
  builds version 0.1.8 and executes its actual retry body in the native fixture.
  The upstream body bypasses an active inhibitor; the repaired body preserves
  pending work, then runs it after the inhibitor clears. Explicit overrides still run.
- The [nix-output-monitor Linux build](https://github.com/nix-forge/nix-conf/actions/runs/38318398666/job/115040557918)
  retains the version 2.2.0 graph-state repair and passes both upstream unit and
  documentation test suites.

The Hyprshell modifier-state fix was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. The upstream recipe and fixed
version 4.10.8 source selection remain unchanged. The
[native Linux build](https://github.com/nix-forge/nix-conf/actions/runs/38318398666/job/115040557982)
uses the configuration's exact unmodified Hyprland dependency at
`663b29b846e4bad17cfa29941f6d2fbb6b61f139` and passes all four existing
modifier timestamp regressions: IPC expiry, wraparound, half-cycle cancellation
and acceptance of the next chord. The existing scoped Cargo test selection stays
unchanged. This supports retaining the repair; it does not establish an
interactive Alt+Tab session or justify advancing Hyprland's own runtime guard.

The Actual CSS case workaround was retired at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. Actual 26.10 removed the
uppercase `Themes` directory that collided with lowercase `themes` in 26.9.
The [unmodified Darwin package proof](https://github.com/nix-forge/nix-conf/actions/runs/38322581431/job/115055022916)
verifies the exact lowercase directory entries and all five stylesheet imports
and exports, then builds the ordinary package. Its installed Node 24.21 runtime
writes, closes and reopens a native SQLite database; the packaged server starts,
migrates its account database, and serves its installed page and declared assets.
The required Darwin `actual-runtime` check preserves those runtime checks using
the configured service's package and its selected Node dependency, with only
loopback networking allowed in the strict sandbox.

The nh Darwin HOME fix was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. Its version 4.4.2 recipe and
fixed source selection remain unchanged. The
[native Darwin build](https://github.com/nix-forge/nix-conf/actions/runs/38324209549/job/115059018442)
preserves the upstream Cargo test selection and passes those Rust suites. The
exact absolute-HOME regression passes in the normal suite and an additional
named invocation. The existing version predicate still bypasses this fix for
newer upstream releases.

The Prism Launcher Darwin watcher test fix was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. The selected package is 11.1.1;
its upstream resource-test source is identical to 11.1.0. The
[native paired proof](https://github.com/nix-forge/nix-conf/actions/runs/38322581431/job/115055022809)
measures a valid but unavailable Qt directory-watch prerequisite in the strict
sandbox and reproduces the original resource-removal failure. Both the existing
and improved repairs skip only that case; all 20 other CTest targets pass. The
improved test first asserts that its temporary directory is valid and exists.
Outside the sandbox, the actual exported resource-test binary passes its full
suite with no skips, so the capability check does not bypass assertions when
watching is available.

The Hyprland subsurface repair was reviewed at
`663b29b846e4bad17cfa29941f6d2fbb6b61f139`. The critical subsurface,
compositor and subcompositor sources remain byte-identical to the previously
reviewed revision. The
[native paired VM proof](https://github.com/nix-forge/nix-conf/actions/runs/38322581431/job/115055022924)
first verifies the software parent display and an unmodified child-first control.
Its actual unmodified compositor then reproduces the precise parent-position
failure; the repaired compositor passes orphan, disconnect, color-feedback and
child-first lifecycle scenarios with clean exit. The production patch is unchanged.

The Claude Code packaging repair was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. The selected vendor package is
2.1.292, with source SHA-256
`dfabaa49a309abe3229719ecfaf41d557c831168b2b642cf2c24e7ab0fc40291`.
The [native Darwin proof](https://github.com/nix-forge/nix-conf/actions/runs/38326427698/job/115066059454)
builds it in the strict sandbox with the existing install-check override, checks
both executable entrypoints, verifies arm64 architecture and inspects the native
loader. Apple's signature integrity check passes for the preserved vendor
signature. The vendor program is not executed; these checks do not establish
runtime correctness, notarization or certificate trust. The repair remains scoped
to strict packaging and disabling the vendor install check.

1. Add `temporary/<name>.nix`, following an existing record. Put its patch data
   under `temporary/patches/`. Use a concrete removal condition and the revision
   of the input that owns the broken source or recipe.
2. Register the file in `temporary/default.nix`. For package fixes, add application
   and platform conditions to `packages.nix`, overriding the existing attribute.
   Function overrides such as `wrapFirefox` use the same attribute selection.
   Keep permanent overlay composition in `default.nix`. For module fixes, select
   `fixes.apply "<name>" inputs.<upstream>` in the owning module's `imports`.
3. Add a package or module evaluation case in `tests/nix/temporary-fixes.nix`.
   Keep the regression reproduction or upstream test with the fix's evidence.
4. Run `just temporary-fixes-check` after changing a fix or updating inputs.
   The flake check evaluates packages for all three supported platforms. It
   forces revision review for every applicable registered package and module
   fix, including disabled features.
   Normal `nix flake check` and `just update-all` also evaluate this check.
5. When a guard fails, inspect the new pinned source and test the package or module without
   the workaround on the affected platform. If fixed, remove the record, registration,
   application, patch, and obsolete check case together. Remove the attribute
   override from `packages.nix` only when no other customization remains. Keep
   the module's package selection. For module fixes, remove the registered fix's
   import and restore the upstream module. If still
   broken, update the reviewed revision or supported range only after validating
   that the workaround is still needed and works.

The check performs evaluation and tests guard behavior. It does not build every
package or demonstrate runtime correctness. It needs no live GitHub status
request, so normal evaluation remains reproducible and works with cached inputs.
It does not send notifications or poll upstream while the lockfile is unchanged.
