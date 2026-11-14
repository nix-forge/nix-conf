# Project layout research

Reviewed: 2026-10-11. Scope: the current root working tree at starting commit
`84e37f5d83e1b218ce8c2c843fe3f9ead479b12c` and the four independent submodules.
Existing staged, unstaged, and untracked source files form the working inventory.
Counts describe the inventory before the moves below.

## Answer

Keep the existing repository ownership and the framework's public module paths.
Group the accumulated research under `docs/research/`, group target-local
configuration by domain, and put helper programs beside the modules that own
them. Replace meaningless extraction sequence numbers with names that identify
the fixture or contract when the contents establish that meaning. Use Python
module names that can be imported normally. Preserve installed command names,
secret names, units, host identifiers, and public feature selectors.

This is a structural change. It should not change enabled behavior or rebuild
package repositories merely to make their directory names match the root.

## Inventory and local findings

The root owns host policy, home profiles, reusable workstation features,
integration, validation, and public guidance. [CONTRIBUTING.md](../../CONTRIBUTING.md) documents those
boundaries. The root has 1,765 existing tracked or nonignored untracked files.
Gitlinks and deleted files do not count as source files. The inventory excludes
ignored environments, build results, dependency installations, and raw captures.

| Root tree | Existing files | Purpose and decision |
| --- | ---: | --- |
| `modules/` | 429 | Reusable system, home, and shared modules; preserve selectors. |
| `docs/` | 344 | User guide, operational guidance, research, reviewed assets, agent guidance. Group research. |
| `tests/` | 333 | Domain suites, Nix behavior checks, native probes, fixtures. Keep test ownership local. |
| `hosts/` | 273 | System targets, local policy, sealed artifacts. Group local modules by domain. |
| `homes/` | 101 | Home targets, local helpers, shared policy. Group local modules and helpers. |
| `flake/` | 95 | Outputs, development tooling, checks, operational entry points. Keep separate from runtime modules. |
| `overlays/` | 80 | Input adjustments, permanent variants, temporary patches and guards. Preserve lifecycle split. |
| `templates/` | 24 | Runnable public examples and generated source templates. Keep independent examples coherent. |
| `lib/` | 17 | Shared helpers exported explicitly. Do not create automatic imports. |
| `scripts/` | 7 | Repository operations and formatter helpers. Feature runtime programs belong with their modules. |
| `site/` | 5 | Site configuration, rendering support, CSS. Keep publishing machinery separate from content. |
| `.github/` | 19 | Workflows, issue templates, CI integration. Preserve platform-reserved location. |
| `security/`, `fuzz/`, `.vscode/` | 4 | Security metadata, fuzz entry point, editor configuration. Existing locations are recognizable. |
| Root files | 34 | Flake, locks, policy, language tools, public governance. Keep tool-discovered filenames stable. |

The root's reusable modules divide into `home`, `nixos`, `darwin`, and `shared`.
Those are semantic boundaries for different module classes, not arbitrary
folders. Tests already use domain directories. Their fixture placement is more
useful than a single central fixtures directory. `flake/dev/` already separates
focused checks and source scripts from deployment outputs.

The documentation snapshot has 237 loose files, of which 178 have the
`-research.md` suffix. The public guide already occupies `docs/guide/`; agent
instructions, publication assets, and document templates already have dedicated
directories. This justifies a research collection without inventing a second
parallel beginner guide or renaming the existing guide.

The root has 209 Python source files; 111 have a hyphen in the basename. Some
are command entry points or subprocess fixtures, so a wholesale rename is not
justified. Importable code and reusable helpers should use underscore names.
Installed commands can retain familiar hyphenated names through Nix wrappers.

### Independent repositories

| Repository | Existing files | Starting revision | Layout assessment |
| --- | ---: | --- | --- |
| `pkgs/` | 1,115 | `8c4f1a824810fc5b7826e1183e7946752a7391fc` | `pkgs/by-name/<prefix>/<name>` is a documented package convention. Recipes, sources, patches, and tests stay with each package. |
| `nix-config-framework/` | 107 | `076e8abfad029c50e3962c9de29918090d6648ad` | `lib/`, `flake-module.nix`, examples, and discovery fixtures have clear owners. Module contracts govern root moves. |
| `nix-seal/` | 262 | `560f8d43cb6edb9ac4a05d2c43423f201ef792e7` | Rust `crates/`, Nix integration `nix/`, JSON `schemas/`, fuzzing, and supply-chain metadata are distinct interfaces. Preserve them. |
| `nix-homelab/` | 433 | `7e96eb138ae4342c44dd6e1f4fa9a6545331f967` | Domain `modules/` and domain/VM tests match service ownership; its existing `docs/research/` supports the root documentation proposal. |

These are separate repositories with their own public outputs, checks, and
release history. Their trees and README conventions were inventoried. No
submodule files were edited or tested by this research. Root structural changes preserve all four gitlinks and leave submodule work
with its owning repository.

## Sources and constraints

### Nix discovery is an interface

The [Nix builtins manual](https://nix.dev/manual/nix/2.24/language/builtins.html#import)
explains that importing a directory loads its `default.nix` and that `readDir`
returns entry names and types. Nix does not impose this project's recursive
module policy. That policy comes from [the pinned framework implementation](../../nix-config-framework/lib/default.nix).
The upstream manual was retrieved on 2026-10-11; the linked version is 2.24.

Local inspection of `selectorEntries`, `mkModuleSet`, `mkSharedModuleSet`, and
`readTargetSpecs` establishes these contracts:

- Reusable module selectors join every directory segment and filename stem
  with a hyphen. Moving a reusable module changes selectors and can introduce
  collisions, even if its contents are identical.
- A reusable directory without `default.nix` aggregates recursively discovered
  modules. Adding `default.nix` changes the boundary to that module's imports.
- Every visible regular `.nix` below a target's `local/` becomes a module,
  including files below domain directories. A local domain `default.nix` does
  not stop recursive discovery. It must not import siblings again.
- The discovery code excludes hidden paths and a directory named `archive`.
  A directory named `scripts`, `assets`, or `lib` is not an exclusion.
- Shared modules use class envelopes. A source helper returning an ordinary
  expression is not interchangeable with a discovered shared module.

The [NixOS module manual](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
describes module `imports` as composition of configuration modules. This
supports verifying evaluated configuration after moves; a parse check alone
cannot establish module equivalence. Retrieved 2026-10-11.

Therefore target-local moves are preferable to public feature path changes.
Keep `.nix` data and helper expressions outside auto-import trees or use the
repository's documented module `lib` exports. Preserve module order where code
uses order-sensitive constructs and test observable generated results.

### Naming follows language and consumer

[PEP 8](https://peps.python.org/pep-0008/#package-and-module-names)
recommends lowercase Python module names and underscores for readability. The
[Python module tutorial](https://docs.python.org/3/tutorial/modules.html#the-module-search-path)
explains that imports locate `<module>.py` using `sys.path`, which initially
includes the input script's directory. Both were retrieved on 2026-10-11.

This means moving a Python script can break sibling imports even after its Nix
source path is updated. Update the packaging import lookup, tests, static
analysis exceptions, and CLI wrapper together. Do not rename a public command
just because its implementation becomes `snake_case.py`. Keep lowercase
hyphenated Nix and Markdown filenames unless a consumer requires another form.
Retain framework `default.nix`, language manifests, locks, and platform-reserved
filenames.

Generated fixture names such as `fixture_<suite>-generated-1.py.in` or
`systemctl_running_writer.py` encode extraction order or old line numbers. Meaningful
names should state the contract or fake behavior. A fixture that writes a
specific temporary file should retain the behavior and extension, and its test
must reference the new path explicitly. Do not infer the name from its sequence
number or rename every fixture by one global replacement.

### Documentation grouping serves reader needs

[Diataxis's map](https://diataxis.fr/map/) distinguishes tutorials, how-to guides,
reference, and explanation by reader need. It does not require fixed directory
names. Retrieved 2026-10-11. The recommendation to isolate research is local
judgment based on the number of accumulated notes and the guide already present.

[The site configuration](../../site/mkdocs.yml) declares strict validation and a curated guide navigation.
`docs/README.md` already provides a public landing page. Keep those reader entry
points, introduce a research index, and update the research-authoring guidance.
Rewrite relative links based on both moved source and destination paths. Also
update linked assets, source links, literal documentation paths in checks,
Nix comments, publishing scripts, and security-tool path policies. Existing
external GitHub links cannot be discovered solely by a relative-link checker.
Avoid retaining duplicate complete files under old names. If an old public URL
needs a redirect, give it a deliberate lightweight compatibility page.

## Implementation recommendations

1. Move existing loose research notes to `docs/research/` with stable basenames.
   A collection index can provide topic groups without another immediate bulk
   rename into many guessed topic directories.
2. Group remaining target-local modules into domains that already appear in the
   repository, such as `desktop`, `development`, `network`, `security`,
   `storage`, and `system`. Use short names within each domain.
3. Move helper scripts and asset templates with their owning domain. Update
   relative imports, Nix package source references, fixtures, tooling includes,
   static analysis exceptions, and published source links in the same patch.
4. Replace line-number and extraction-number names where the test and contents
   establish a stable purpose. Preserve distinct fake programs and template
   fixtures rather than combining different behavior into one ambiguous file.
5. Add concise layout guidance with actual repository responsibilities, the
   selector warning, and source naming conventions. Avoid a large tree listing
   that goes stale after every new file.
6. Keep root governance files, manifests, lockfiles, public feature selectors,
   submodule paths, temporary-fix registry, and reviewed assets' ownership.

## Validation and limits

This research used read-only Git inventories, configuration/source inspection,
and primary-source web retrieval. The research did not run builds, activate targets, decrypt artifacts, or
execute native runtime checks. It does not certify every
source file's correctness. It covers directory ownership and naming conventions
across all root domains and the four submodule inventories.

The coordinator should verify an explicit old-to-new path map, preserve existing
working contents, scan for stale references, and run documentation links and
focused Python/template checks. Evaluation must cover every affected target,
including public module interfaces and generated configuration. On the desktop
host, heavy checks run through `workstation-task`; a desktop closure builds only
on the desktop host. Darwin-native checks require a Darwin host. Moving files
without changing behavior does not require deployment or activation.

New source files must enter the Nix source set deliberately. A default Git-based
flake invocation does not automatically validate untracked moved files.

## Reviewed fixture moves

All mappings below follow inspected fixture contents and their literal Python
callers. No files in these source directories were changed by this researcher.
Names in the first table are relative to `tests/browsers/fixtures/`.

| Existing basename | Recommended basename | Observed behavior |
| --- | --- | --- |
| `check_apple_emoji-58.cjs` | `apple-emoji-font-load.cjs` | Loads local Apple emoji FontFace. |
| `check_apple_emoji-64.cjs` | `apple-emoji-canvas-metrics.cjs` | Compares sample widths and colored pixels. |
| `check_font_rendering-391.cjs` | `font-element-metrics.cjs` | Reads an element's text, bounds, and computed font. |
| `check_font_rendering-422.cjs` | `font-descriptor-load.cjs` | Loads and checks a supplied CSS font descriptor. |
| `check_font_rendering-440.cjs` | `local-font-name-load.cjs` | Compares full-name and PostScript-name FontFace lookup. |
| `check_font_rendering-458.cjs` | `font-compatibility-metrics.cjs` | Measures style, variable, monospace, generic, and emoji behavior. |
| `check_font_rendering-719.cjs` | `webfont-load-and-ligatures.cjs` | Loads Google webfonts and checks symbol ligature width. |
| `check_font_rendering-758.cjs` | `ublock-filter-list-selection.cjs` | Applies and reports uBlock filter lists. |
| `check_font_rendering-813.cjs` | `multilingual-fallback-comparison.cjs` | Compares generic canvas output to installed language fonts. |
| `check_font_rendering-889.cjs` | `numeric-digit-rectangles.cjs` | Reports digit bounds for screenshot pixel checks. |
| `check_font_rendering-916.cjs` | `firefox-graphics-snapshot.cjs` | Reads Firefox graphics troubleshooting metadata. |
| `check_font_rendering-1178.cjs` | `apple-system-stack-font-load.cjs` | Loads SF Pro web/local faces for ordinary and private-use text. |
| `check_font_rendering-1188.cjs` | `apple-system-stack-metrics.cjs` | Compares system, named, downloaded, fallback, and private-use stacks. |
| `check_font_rendering-1347.cjs` | `apple-platform-namespace-metrics.cjs` | Measures Apple platform aliases and configured sans availability. |
| `check_font_rendering-1462.cjs` | `missing-named-stack-metrics.cjs` | Measures YouTube and synthetic unavailable-first-family stacks. |
| `check_hdr_output-268.cjs` | `video-playback-quality.cjs` | Reports video frames, errors, resolution, pause/fullscreen state. |
| `check_mutant_emoji-93.cjs` | `mutant-emoji-canvas-metrics.cjs` | Compares Mutant emoji widths and populates custom glyph examples. |

CI mappings are relative to `tests/ci/fixtures/`.

| Existing basename | Recommended basename | Observed behavior |
| --- | --- | --- |
| `test_ci_inventory-21.nix.in` | `hosted-check-selection.nix.in` | Tests platform check additions and hosted exclusions. |
| `test_ci_inventory-115.nix.in` | `configuration-inventory.nix.in` | Tests host addition/removal and lazy foreign closure evaluation. |
| `test_theme_discovery-54.nix.in` | `theme-target-discovery.nix.in` | Evaluates the production shared theme importer on changing targets. |

The CI tests require daemon-capable pytest selection and configured
`NIX_TEST_NIXPKGS` and `NIX_TEST_FRAMEWORK`. The ordinary `python-tests` check
excludes `nix_daemon`, so its pass does not establish these discovery contracts.
CJS verification uses the repository's `npm run check`, whose globs already
cover these files. Native browser rendering remains a separate runtime check;
renaming unchanged fixture bytes does not alone justify a native browser run.

## Implemented layout

The root now keeps research in `docs/research/`, runbooks in `docs/operations/`,
and dated reviews in `docs/reviews/`. Each collection has an index. Existing
guide URLs, contributor conventions, security policies, and reviewed assets
retain their locations.

Homelab music bootstrap programs are beside their music modules. Credential
transport programs are together under the desktop
`local/homelab/credentials/`; their sibling workers stay with them. Actual's
CLI and lifecycle scripts are together under `local/homelab/actual/scripts/`.
The vault importer suite moved into `tests/homelab/`, so the normal root runner
discovers it. Its Nix check now includes the credential sources and sealed-file
inventories that its assertions need.

Seventeen browser probes and three CI fixtures use purpose-based names instead
of extraction line numbers. LinearMouse and Feishin activation sources also
identify their lifecycle roles. LibreOffice's source assets sit beside its
owning module in an assets directory without changing the `libreoffice` selector.

The [layout guide](../layout.md) records the ongoing naming and ownership policy.

### Source and fixture verification

Verification on Linux covered the implemented moves and their consumers:

| Check | Result |
| --- | --- |
| Relocation manifest | 273 destinations present; original file modes preserved |
| Public reusable Nix module paths | No changes |
| Stale complete source paths and relative Markdown links | No introduced failures |
| Focused homelab, caption and documentation-reference suites | 105 tests and 28 subtests passed |
| Affected Python sources | Ruff lint and formatting passed for 31 files |
| Affected Nix sources | nixfmt validation passed for 16 files |
| Renamed browser programs | Node syntax passed for 17 byte-identical sources |
| Collection and contributor guidance | Rumdl passed for 233 files |
| Documentation publication scan and patch whitespace | Passed |

The Nix behavior-check build is queued behind another workload under the
required desktop runner. Broader check builds and host closure evaluations
remain unverified. The source and fixture results above do not establish a
successful system build or native Darwin runtime behavior. No activation was
performed.
