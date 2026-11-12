# Overrides and overlays

Temporary package and upstream module fixes live in [`temporary/`](temporary/default.nix).
Long-lived package selection lives in [`permanent/`](permanent/). The reusable Jellyfin variant
lives in `nixpkgs-personal`; `packages.nix` selects it. Feishin uses the official
Nixpkgs application.
[`default.nix`](default.nix) is a Nixpkgs overlay. Each target installs it through
`nixpkgsArgs.overlays`; attached Home Manager configurations share their host's
package set through `useGlobalPkgs`.
[`packages.nix`](packages.nix) owns platform conditions, package sources, and
the order in which fixes apply. It receives the incoming `prev` package set.
Consumers keep their normal upstream module imports when an input-module
replacement is retired.

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
`pkgs.gtksourceview4` itself keeps its upstream definition. The
`pkgs.grimblast-region` variant is defined in `nixpkgs-personal`, while
`pkgs.grimblast` retains its normal behavior.

The overlay also owns the Determinate Nix package selection, its scoped Darwin
test repair, Actual secret-log redaction on both platforms, and the Linux Zen
wrapper repair. The
Determinate modules configure the service and daemon settings.

The developer formatter selects `nixf-flake-builtins` for its diagnostic tool.
The frontend's metadata generator links the same selected Nix flake library and
registers its three real flake primops. This retains unknown-builtin diagnostics
and the ordinary Nix expression calls. Native install checks require the valid
flake names to pass and a misspelled builtin to fail. Retire the repair when the
unmodified frontend provides that metadata and passes those checks.

T3 Code uses the official Nixpkgs package at its separately locked release pin.
The Darwin-only `t3code-darwin-workspace-shims` repair extends the standard
shebang patching to generated workspace executables after upstream preparation.
The native reproduction fails with the system shell and succeeds with the Nix
shell while preserving every shim body, mode and link. Retire this repair when
the official recipe or pnpm's helper lookup handles those workspace shims.

The ARM Darwin-only `t3code-darwin-vendor-gui` integration selects the unmodified,
Developer ID signed official 0.1.6 Beta app archive. It replaces only the GUI
application and external desktop launcher; the official Nixpkgs CLI, persistent
server, unwrapped payload, resource monitor and provider configuration remain
selected. No signed bundle file is patched, stripped, wrapped or re-signed. The
old outer-plist repair and its regression are retired together because the
vendor app already supplies the canonical identifier and usage description.

The integration is restricted to the reviewed release and input revision. Retire
it when the selected official Nixpkgs Darwin package provides the same signed
vendor bundle and passes native identity, notarization, provider and data
continuity checks. A successful package build is not Local Network consent or a
connection fix. Switching from shared Electron to the signed app requires a
separate no-initialization catalog/Keychain and user-data migration review;
preserve encrypted data and stop on unexpected initialization or mutation.

Rift 0.7.2 keeps automatic workspace following suppressed after wake or unlock
until it sees mouse activity or a Rift command. The temporary native app-switch
repair forwards keyboard interaction as a key-free intent event, so unbound macOS
shortcuts such as Command+Tab can clear that guard. The shortcut remains native;
Rift's own synthetic keys and repeats do not count as fresh input. Native input
and lifecycle regressions cover forwarding and guard release without changing
focus or layout. Retire the repair when unmodified Rift passes those checks and
the native wake/unlock reproduction.

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

The permanent Determinate overlay selects the actual owning Nix component scope
and repairs its libgit2 trailing-slash cleanup on Linux and Darwin. The repair
retains the upstream main suite and adds the complete utility suite, including
single- and multiple-slash symlink target preservation. Other libgit2 packages
keep their upstream definitions. The Darwin functional-test workaround remains
a separate temporary fix and preserves the combined package's unit gates.

Determinate's NixOS module factory receives the libgit2 cleanup repair. Its
global Sentry dependency remains unchanged, and the upstream module still owns
`nix.package` and the daemon command. Retain factory routing until the libgit2
repair is retired. Sentry now uses its upstream report-lock implementation,
covered by the retained native regression.

The [Sentry investigation and regression checks](../docs/operations/sentry-crashpad-lock.md)
describe the retained upstream regression and retirement evidence. The upstream regression retains strict output handling by default; noisy-contention
acceptance requires an explicit argument in an isolated baseline fixture.
Region-only Grimblast behavior is a personal package variant. Module-specific
Git options and browser flags stay with the module that owns those options.

Use `prev` for the incoming package in an overlay. Preserve the existing scope
when moving a local override. The GtkSourceView fix here still applies only to
Virt Manager's dependency. See the [Nixpkgs overlay and override documentation](https://nixos.org/manual/nixpkgs/unstable/index.html#chap-overlays).

Module fixes use the same registry and revision guard as package fixes. Their
`apply` function takes the upstream input and returns a module. The owning module
imports that result, as the Neovim module does for `stylix-nvf`. Construct its
registry with `{ inherit inputs lib; }` so import resolution does not depend on
`config._module.args.pkgs`. Module fixes stay outside the Nixpkgs overlay in `packages.nix`; they need no package version range.
When a fix replaces an exported upstream module, apply it at the flake's input boundary so
the consuming configuration does not need patch-specific imports.

The QEMU user-mode release backport is retired: the selected Nixpkgs already
provides 11.1.2 with the same release source. The binfmt wrapper and interpreter
sandbox configuration remain with their owning modules.

## Temporary fix lifecycle

The Blocky multiple-DNSKEY backport applies upstream
[PR #2293](https://github.com/0xERR0R/blocky/pull/2293) to 0.35.0. The validator
previously selected the first DS-matched key and rejected a valid DNSKEY RRset
when another trusted key signed it. The fix tries the trusted candidates while
bounding validation attempts. Its package check runs the offline validator suite,
including second-key acceptance, untrusted-key rejection, and verification-limit
regressions. Encrypted upstreams, filtering, rebinding protection, and DNSSEC
settings remain with their existing owners. Retire the backport when the selected
source includes the fix and passes those regressions without it.

Moonfin's caption background repair is retired at 3.0.0, revision
`eb43b626f6f9239e1dd050e529de28702b08038c`. Its unmodified style writer
selects and clears the background box and padding. The retained Dart check
passes opacity transitions, omitted values, color alpha, bold and authored ASS
handling; an exact broken-property control reproduces `missing box`.
The unmodified Linux package also builds with its install checks.

### October 2026 audit of the current pins

The integration retires the Claude sandbox, Sentry report-lock, TypeScript
dependency-hash, QEMU user-mode release and Stirling PDF 3 backports. Their
selected upstream recipes now provide those repairs. The remaining audit uses
Nixpkgs `02c087f3fe673c9e317f206a627cb6b910336dbe` and the
independently guarded input revisions recorded in each fix. A merged upstream
change alone does not retire a repair: the selected source must contain it.
The already retired Actual and Rclone release backports, portal compiler repair,
Home Manager portal adapter and separate Zoom input remain retired.

| Fixes | Why they remain |
| --- | --- |
| `home-manager-protected-apps` | Upstream copyApps still lacks exclusions for independently managed bundles. |
| `darwin-application-signatures` | Vendor bundle preservation and final bundle sealing remain necessary. Only Signal needs the added signing tool; AeroSpace and Zoom retain their vendor bundles without it. |
| `nu-scripts-pytest-lists` | The selected completion still contains both invalid semicolon-separated choice lists. |
| `nixf-flake-builtins` | The selected metadata generator still registers expression builtins without the flake primops. |
| `jellyfin-caption-defaults` | Jellyfin 12.2 still mutates shared defaults; the existing regression fails against unmodified source and passes after the repair. |
| `prowlarr-torrentdownload`, `microsocks-credential-files`, `actual-redact-secret-log` | The selected sources still lack the title/search normalization, credential-file interface and log redaction respectively. |
| `deploy-rs-confirmation-path`, `deploy-rs-darwin-tests` | The pinned helper retains the lexical-path comparison and native FSEvents dependency. Keep the runtime correction separate from the three sandbox test exclusions. |
| `determinate-libgit2-trailing-slash`, `determinate-libgit2-module`, `determinate-darwin-tests` | The owning dependency sources lack the cleanup fix, the module still needs factory routing, and the Darwin functional suite still registers the sandbox-incompatible Sentry case. |
| `ghostty-bash-prompt`, `gtksourceview-xvfb`, `hypridle-condition-inhibitors` | Their selected sources retain the prompt marker conflict, Xvfb reset race and inhibitor bypass. |
| `nom-quadratic-build-plan`, `nom-named-activities` | Monitor 2.2.0 retains linear root deletion and lacks named activity type 10113. |
| `hyprland-subsurface`, `hyprland-subsurface-rounding` | Both complete repairs still apply to the selected compositor source. |
| `hyprshell-modifiers`, `hyprshell-workspace-schema`, `hyprshell-workspace-identity` | All three repairs remain absent from 4.10.8; the identity patch depends on applying the other two first. |
| `nh-darwin-home`, `prismlauncher-darwin-tests` | nh 4.4.2 still sets empty elevated HOME; Prism 11.1.1 still assumes native watcher availability. |
| `nixos-anywhere-ssh-host-check` | The pinned installer still disables host-key verification before argument parsing. |
| `stylix-gtk-flatpak-polarity`, `stylix-nvf`, `stylix-rofi` | The selected modules retain incomplete Flatpak polarity handling and both deprecated option assignments. |
| `swift-clang-hardening`, `zen-wrapper-copy` | The selected compiler wrapper and Firefox wrapper still lack the required hardening forwarding and compatible copy command. |

Keep both permanent overlays: the personal package collection supplies intentional
variants, and Determinate selects its owning Nix component scope. Neither is a
temporary release backport. This audit inspected pinned recipes and available
sources and reused the recorded native evidence below; it did not repeat every
package build or interactive regression.

### Guard and retirement procedure

Every registered fix records its reason, upstream link, removal condition, input
path, and an explicitly reviewed input revision. Do not derive
`reviewedRevision` from the current lockfile at evaluation time. That would make
the check accept every update automatically.

The guard throws a review error when that input changes. This catches recipe
changes and backports even when a package keeps the same version. The portal fix
tracks `hyprland.inputs.xdph`; tracking only the outer Hyprland revision would
miss an independent portal input update.

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

The Actual 26.10 release backport and Rclone 1.75.1 security backport were
retired at Nixpkgs `7fd4004d0511991fff3a0524856a9be09e28c5f0`.
The incoming Actual recipe already selects the same source, translations, Node 24
and dependency cache covered by the unmodified native proof above. Rclone selects
the same 1.75.1 source and dependency hash as its former backport. Package consumers
now use those upstream recipes; Actual's independent secret-log repair and required
runtime check remain in place.

The nh Darwin HOME fix was reviewed at Nixpkgs
`e7439b6b14ad3cc35d05608ebca9bce01a25f5f8`. Its version 4.4.2 recipe and
fixed source selection remain unchanged. The
[native Darwin build](https://github.com/nix-forge/nix-conf/actions/runs/38324209549/job/115059018442)
preserves the upstream Cargo test selection and passes those Rust suites. The
exact absolute-HOME regression passes in the normal suite and an additional
named invocation. The existing version predicate still bypasses this fix for
newer upstream releases.

The October 2026 retirement review found that Nixpkgs
`7fd4004d0511991fff3a0524856a9be09e28c5f0` already contains the exact Zoom
recipe previously imported through a separate input. The desktop now uses the
upstream module's default package, retaining its portal configuration. Maintainerr
also uses the incoming libvips when it meets sharp's 8.18.7 minimum; only older
standalone consumers need its source backport. Codex and ChatGPT now use the unmodified upstream packages. Their former personal
release pins and managed-app source patch are retired. Host configuration retains
its state-directory and resource-management policy.

The TypeScript language-server cache correction is now in the selected Nixpkgs
recipe. The redundant fix, its guard and its obsolete negative fixtures have
been removed; ordinary package selection resolves directly to upstream.

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

The parent-lifetime repair was subsequently reviewed at Hyprland
`1bd31aaa579a40680ce876e1547e371b60c45522`, with Nixpkgs
`7fd4004d0511991fff3a0524856a9be09e28c5f0`. The current native paired VM
uses an isolated direct DRM software renderer. After protocol and renderer
preflight, the unmodified compositor reproduces the precise parent-position
crash and manager-confirmed core dump. The unchanged patch passes all four
lifecycle scenarios five times each and exits cleanly, as confirmed by both the
original process descriptor and final manager properties. The maintained VM
port preserves those gates. Its separate parent-display check also requires a
real unmodified child-first control and manager-confirmed clean exit; that port
must be validated on the selected native driver and VM after integration.

The Claude Code packaging repair is retired. The selected upstream recipe no
longer requests an unsandboxed build. The [native unmodified-package proof](https://github.com/nix-forge/nix-conf/actions/runs/41228607280/job/124617890275)
builds version 2.1.303 in the strict Darwin sandbox and preserves its original
install checks, executable architecture and vendor signature.

The Determinate Darwin test repair was reviewed at its nested Nix input
`1ef903401b3426fbca74a692e158cca82d7c98ab`, version 3.23.1. The
[native strict-sandbox proof](https://github.com/nix-forge/nix-conf/actions/runs/38327735034/job/115070216612)
reproduces only the Sentry crashdump failure with Crashpad Mach registration
permission denied (1100). The repair preserves `doCheck`, all five original unit
gate derivations, upstream patches and Meson flags. It omits only the Darwin
`main/sentry.sh` registration; native introspection verifies every other test's
registration and execution settings remain unchanged. All five unit gates build
successfully; the functional suite reports 189 passing cases, zero failures and
36 upstream skips. The combined package remains under the strict sandbox, with
only its existing declared local-network allowance for functional tests.

The Deploy Darwin repairs were reviewed at
`45ba3f8c5cb28396fff71671806e2550b464ac86`. The
[native same-binary control](https://github.com/nix-forge/nix-conf/actions/runs/38329944044/job/115077204280)
shows that strict sandboxing prevents FSEvents from starting; with a canonical
temporary directory on the host, all three original watcher cases pass. Ordinary
host directory aliases separately expose a real confirmation-path bug. The
[native source-repair proof](https://github.com/nix-forge/nix-conf/actions/runs/38331485552/job/115081978519)
requires the unmodified helper to pass its real-directory case and fail its
verified symlink-alias case. The repaired helper passes both cases and all three
original watcher cases under the ordinary host environment, without changing
watcher predicates or timeouts. Its complete Rust package checks preserve only
the three existing strict-sandbox capability exclusions; sentinel tests remain
live. The path-normalization repair has its own record and removal condition,
independent of the sandbox-test repair. The required Darwin CI job builds the
actual configured package and executes all five native host regressions using its
selected source and repairs; no manual proof dispatch is needed for this gate.
Linux keeps the unmodified package.

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

The dependency review at Nixpkgs `02c087f3fe673c9e317f206a627cb6b910336dbe`
retains the GTK, Zen wrapper, Swift hardening, Nix Output Monitor, Hypridle,
Hyprshell, AudioMuse loopback, and NH Darwin home fixes.
Source comparison confirms the repaired paths remain applicable; the current
native proofs pass in [run 41226706466](https://github.com/nix-forge/nix-conf/actions/runs/41226706466).
GTK adds an upstream Meson timeout setting; NH adds system SQLite configuration.
Claude's separate unmodified-package proof above supports retiring its override. The Darwin
Determinate test policy also passes against its current nested Nix revision
`9993a12bd434f653d5081b9b35f50900412fece8`.

The Hyprland parent-lifetime repair is retained at
`76edafffc68951a66b094806659ac4823e22c624`. The critical source files
remain byte-identical to the previous review. The
[current paired native VM proof](https://github.com/nix-forge/nix-conf/actions/runs/41226706466/job/124612259173)
passes the unmodified startup control, reproduces the baseline lifetime failure,
and passes the repaired lifecycle scenarios.

Both Deploy repairs are retained at
`1cec0527bd09074bbee6d4461900ce5d58267217`. Upstream changes only
package version metadata and its CLI version declaration; watcher and
confirmation logic and Rust dependencies are unchanged. The
[current native proof](https://github.com/nix-forge/nix-conf/actions/runs/41228607280/job/124617890335)
reproduces the sandbox event-delivery limitation and raw directory-alias timeout.
The identical watcher binary passes its three original cases with a canonical
host directory; the repaired helper passes both ordinary and alias paths.
The full suite retains the existing non-watcher and sentinel assertions.

The Prism capability repair is retained at Nixpkgs
`02c087f3fe673c9e317f206a627cb6b910336dbe`. Its source and package
recipe are unchanged. The [current native proof](https://github.com/nix-forge/nix-conf/actions/runs/41227385502/job/124614264423)
measures unavailable native watching in the sandbox, requires the precise
unmodified failure and capability skips, and passes every other resource case.
The exported actual test binary passes the full resource suite on the host
where the independent prerequisite confirms watcher availability.

Azure CLI 2.91.0 needs Fabric 3.2.3, whose declared Invoke range is
`>=2.0,<3.0`. The current Nixpkgs scope supplies Invoke 3.0.3 and correctly
marks that Fabric dependency broken. The `azure-cli-invoke` repair pins the
non-yanked Invoke 2.2.1 source inside Azure's private interpreter, composing
after Azure's own package overrides. The ordinary Python package set retains
Invoke 3.0.3. The repaired CLI's `withExtensions` method retains this scope and
the packaged Azure DevOps extension. A required native check imports Azure's
actual App Service SSH module with Fabric and Invoke, constructs a connection
without opening it, and checks offline CLI help and extension discovery.
The same private scope grants Darwin local networking to `sshtunnel`'s
unmodified loopback SSH tests, matching the upstream Paramiko recipe. Its
sandbox and complete selected pytest suite remain enabled. The original
Darwin build failed in test setup while resolving `localhost`; the native
repair subsequently passed all 47 selected SSH tests. A separate HTTPX2 timeout
fixture could return EOF before a descheduled caller started waiting. Its mock
now stays open until explicit close, and both immediate and delayed callers
must still raise the same timeout. Production HTTPX2 code is unchanged.
The private Requests telemetry dependency also gets Darwin local networking
for its real loopback HTTP server tests. The [focused Darwin proof](https://github.com/nix-forge/nix-conf/actions/runs/41240432860/job/124653014334)
passes all 81 telemetry tests and CLI integration alongside the SSH and HTTPX2
suites. Retire the repair when the selected dependencies supply compatible
Fabric/Invoke, and their Darwin tests have the required local networking and
deterministic timeout fixtures.

The temporary `nvidia-bin-patchelf` repair rebuilds the NVIDIA command-line
executables from the driver's retained originals, applying RPATH and interpreter
edits separately. The combined invocation can map `.dynamic` read-only and crash
the loader before any library loads ([upstream issue #576412](https://github.com/NixOS/nixpkgs/issues/576412)).
It preserves the selected driver, libraries, kernel modules and upstream checks,
and adds a real `nvidia-smi --help` install check that needs no GPU. Remove the
repair when the upstream builder passes that check without it; deployment also
verifies a live GPU query.

The upstream LinearMouse 0.12 recipe remains selected. Its temporary APFS
extraction repair only excludes alternate streams: otherwise 7zz creates an
`Info.plist:com.apple.quarantine` file inside the signed login helper. Apple's
deep strict signature verifier rejects that extra sealed resource. The required
Darwin check verifies the entire resulting upstream bundle, including the helper;
no bundle contents are patched or re-signed. Retire the repair when the official
recipe extracts the same archive without these extra files and passes that check.
