# Which Nixpkgs functions would improve nix-forge?

Reviewed: 2026-09-08. Scope: `nix-conf` and all seven repositories returned by the
GitHub organization API for `nix-forge`. The findings below record the initial
research. The [implementation follow-up](#implementation-follow-up) records the
subsequent changes and their validation. The
[completion follow-up](#completion-follow-up) records the latest fixes and
supersedes the earlier platform and validation gaps for its named checks.

## Answer

Start with argument escaping and generated-script checks, then narrow build
inputs and remove duplicated library algorithms. Many parts already use the
right helpers. Replacing every `runCommand`, template, or custom traversal would
remove useful behavior in several places.

The strongest opportunities are:

| Order | Owning repository | Concrete improvement |
| --- | --- | --- |
| 1 | nix-conf | Quote configurable shell values with `lib.escapeShellArg`; add checks of rendered scripts or migrate suitable commands to `writeShellApplication`. |
| 1 | nix-seal, nix-conf | Use systemd-specific argument escaping for generated `ExecStart` values, preserving intentional runtime specifiers. |
| 2 | vpn-confinement, nix-conf | Package standalone Python commands with `writers.writePython3Bin`, with an explicit lint policy. |
| 2 | nix-conf, nixpkgs-personal | Narrow individual check inputs with `lib.fileset.toSource` and `unions`, while keeping whole-repository quality scans complete. |
| 2 | nix-seal, vpn-confinement | Replace duplicated grouping, hexadecimal conversion, and remainder algorithms with the corresponding library functions. |
| 3 | nixpkgs-personal | Add explicit file-collision checks to the Apple font aggregate with `buildEnv`. |
| 3 | nix-config-framework | Validate callback values at the option boundary without changing module discovery or selector contracts. |
| 3 | ci | Package developer validation commands with their dependencies while preserving the privileged GitHub action's independent execution model. |
| 4 | nix-conf, nixpkgs-personal | Use `genAttrs`, `mapAttrsToList`, `min`, `max`, and `linkFarm` where they directly express existing behavior. |
| Keep | .github | Continue delegating validation and automation to `ci`; this repository has no Nix implementation to simplify. |

These priorities reflect observed code and migration cost, not measured build-time
or performance gains. The repository sections below distinguish tested examples
from proposals.

## Evidence and scope

The inventory includes configuration, reusable modules, package recipes, native
and interpreted helpers, tests, update tooling, CI, and organization templates.
All repository areas were inventoried; detailed reading concentrated on code
that creates packages, renders commands/configuration, transforms attributes, or
duplicates library behavior. This is not a line-by-line audit of every language
implementation or an exhaustive search of every Noogle function.

The root has 333 tracked Nix files, including 225 under `modules/`, 40 under
`homes/`, 47 under `hosts/`, and 12 under `flake/`. These counts exclude the
separate submodule repositories. Most host/profile files select modules or set
upstream options and have no worthwhile function replacement.

| Repository | Source examined | Nixpkgs compatibility source |
| --- | --- | --- |
| nix-conf | Local `d0c82c0e185efa08f9e5cd605454403cb09b838a` plus existing worktree changes | `c5c4a43b0e8056328ec4529f735cabdb8f1942bb` from the existing lock |
| nixpkgs-personal | Local `pkgs/` at `5d62685c585aab9982b9b2ffbfe57b6abc3b587b` plus existing worktree changes | `801bef6abd86b91e51083066b83fb354a11fc640` |
| nix-config-framework | Local `nix-config-framework/` at `db76717b9c7868d9df052114a1ee2168d3b51423` | `0968519e14f7aa7d3e9b389682bd74d2b51c8ce8` |
| nix-seal | Local `nix-seal/` at `f76477bd8caac37f84553df48b48dc14a1365a9f` | `0968519e14f7aa7d3e9b389682bd74d2b51c8ce8` |
| ci, .github, vpn-confinement | Fresh default-branch checkouts | Exact repository and lock revisions are recorded in their detailed findings below |

Organization coverage was confirmed with both `gh repo list nix-forge` and the
paginated GitHub organization repositories API. Both returned the same seven
public, unarchived repositories. [Organization repository list](https://github.com/orgs/nix-forge/repositories).

Local code links identify the examined working files. Their content can include
uncommitted work and is not necessarily represented by a GitHub commit link.
No existing worktree changes were altered. Remote repositories were inspected
in temporary checkouts without changing their branches or publishing findings.

[Noogle](https://noogle.dev/) provided discovery and reference pages. The locked
Nixpkgs source supplied the compatibility evidence. Noogle's displayed revision
can differ from a repository's lock; its Python writer page did differ from the
package repository's pin. Some direct Noogle URLs, including `replaceVarsWith`
and `testEqualContents`, were unavailable through the browsing tool. Those
functions were checked in pinned source instead.

## Findings for nix-conf

### Shell commands and configurable values

The wallpaper scripts are the best first migration target. For example,
[wallpaper.nix](../modules/home/desktop/wallpaper.nix) supplies an unescaped
directory to [wallpaper-add.sh](../modules/home/desktop/scripts/wallpaper-add.sh),
which places it inside single quotes. An isolated substitution using a directory
containing an apostrophe makes `bash -n` fail. This is a concrete robustness
problem for configurable paths, regardless of which builder packages the script.

Use `lib.escapeShellArg` at the Nix-to-shell boundary and remove the template's
surrounding quotes around that replacement. Shell syntax and already-quoted
argument lists need separate treatment. `replaceVarsWith` quotes the arguments
to its substitution command, but it cannot know the syntax of the resulting
file. [Noogle escaping reference](https://noogle.dev/f/lib/strings/escapeShellArg/),
[pinned replacement builder](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/replace-vars/replace-vars-with.nix).

`writeShellApplication` is a good fit for wallpaper commands and other installed
Bash programs with external commands. It supplies the interpreter, strict Bash
options, runtime dependencies, and syntax/ShellCheck validation. Preserve
`inheritPath = false` for helpers that currently replace `PATH`. Other commands
intentionally use the caller's Nix CLI or native macOS utilities and need a
different dependency policy. [Noogle writer reference](https://noogle.dev/f/pkgs/writeShellApplication/),
[pinned writer implementation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/trivial-builders/default.nix#L260).

A migration shape, assuming the script body has been separated from its current
shebang, strict-mode setup, and PATH assignment:

```nix
pkgs.writeShellApplication {
  name = "desktop-wallpaper-add";
  runtimeInputs = [ pkgs.coreutils pkgs.file ];
  inheritPath = false;
  text = ''
    destination_directory=${lib.escapeShellArg cfg.directory}
    # Continue with the script body using "$destination_directory".
  '';
}
```

This is an outline, not a complete replacement program. The tested example used
the actual importer body. It copied a synthetic image into a path containing an
apostrophe and spaces, retained mode `0600` for the file and `0700` for its
directory, and worked with a caller PATH containing no tools. Missing arguments
still returned exit code 64.

`runtimeEnv` is useful for deliberate environment variables, but it is not
automatically the best way to inject every local value. A first experiment using
an apostrophe-containing exported value failed the writer's ShellCheck step with
SC2089/SC2090. Direct assignment using `escapeShellArg` passed with ShellCheck
enabled. This report does not recommend globally excluding those checks.

For scripts whose current templates are useful, retain `replaceVarsWith` and
add Bash syntax and ShellCheck validation in `postCheck`. Its forced check phase
already calls that hook. This preserves missing/unused-placeholder checks without
rewriting the script. Check the generated file, since linting the `.in` file alone
cannot catch invalid substituted values. The pinned builder does not permit
replacing its forced `checkPhase` through its argument set.

Apply that decision individually to
[clipboard](../modules/home/desktop/clipboard.nix),
[capture](../modules/home/desktop/capture.nix),
[wallpaper](../modules/home/desktop/wallpaper.nix),
[VM helpers](../modules/nixos/virtualisation/libvirt.nix), and
[local-control helpers](../homes/macbook-pro-m4/local/local-control/runtime-helpers.nix).
The latter two have extensive behavior and permission checks that packaging must
preserve. Activation fragments such as
[Actual setup](../modules/home/actual.nix) should retain their Home Manager
activation ordering and dry-run handling.

`writeShellScriptBin` remains appropriate for small scripts with explicit
executable paths. It adds a shebang, executable installation, and syntax checking;
it does not provide ShellCheck or a runtime dependency PATH. Existing test doubles
in [checks.nix](../flake/dev/checks.nix) already use it appropriately.
[Noogle reference](https://noogle.dev/f/pkgs/writeShellScriptBin/).

### Standalone Python programs

[windows-vm.nix](../modules/nixos/virtualisation/windows-vm.nix) currently creates
a `writeShellApplication` whose only job is to execute
[windows-vm-render-seed.py](../modules/nixos/virtualisation/scripts/windows-vm-render-seed.py).
A Python writer removes that shell layer and associates the interpreter with
the actual program:

```nix
pkgs.writers.writePython3Bin "windows-vm-render-seed" {
  # Keep repository Ruff formatting; retain the other Flake8 checks.
  flakeIgnore = [ "E501" ];
} ./scripts/windows-vm-render-seed.py
```

The existing script failed the default writer build on Flake8's 79-column E501
rule. The example above built successfully against the root lock. Its packaged
CLI passed a synthetic XML-escaping and output-permissions test without relying
on the caller PATH. All eight existing seed-renderer unit tests also passed on
the unchanged source. The writer's lint step supplements behavior tests and the
repository's Ruff/type checks. It does not replace them.
[Noogle Python writer](https://noogle.dev/f/pkgs/writers/writePython3Bin/),
[pinned interpreter and Flake8 selection](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/writers/scripts.nix#L1178).

The same pattern can package the standalone updater in
[codex.nix](../modules/home/dev/agentic-tui/codex.nix) with
`libraries = [ pkgs.python3Packages.tomlkit ];`. Keep its activation wrapper's
argument defaults, mutable-file ownership, and `run` behavior. This candidate
was inspected but not built. Browser, identity, and local-control Python helpers
need individual checks for adjacent imports, resources, and `__file__` use before
moving a source file into a standalone store executable.

### Generated service arguments

[wallpaper.nix](../modules/home/desktop/wallpaper.nix) line 1236 builds the video
wallpaper service's `ExecStart` using shell escaping. systemd has its own
argument parsing and expands `%` specifiers and `$` variables. A shell escaping
function does not cover that grammar.

Use the semantics of NixOS `utils.escapeSystemdExecArgs` for literal argument
lists, keeping the executable, flags, and values as separate list entries.
The utility lives in `nixos/lib/utils.nix`; it is not a general
`lib.escapeSystemdExecArgs` function. For Home Manager, establish an explicit
supported way to access or share that behavior. Do not assume the NixOS module
argument `utils` exists there. The nix-seal findings below include a reproduced
case and explain how to preserve intentional `%t` expansion.
[Pinned systemd utility](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/lib/utils.nix#L164).

### Build inputs and generated configuration

Use `lib.fileset.toSource` with `unions` for focused tests and local compiled
helpers. [fonts.nix](../flake/dev/fonts.nix) already demonstrates this well.
[secure-files-rs/package.nix](../homes/macbook-pro-m4/local/local-control/runtime-helpers.nix)
uses `cleanSource ./.`; an explicit set containing its Cargo manifests, source,
and required fixtures can exclude unrelated files from that derivation.
Inventory Cargo/build-script inputs before narrowing it. This is a proposed
dependency change, not a demonstrated build-speed improvement.
[Noogle fileset reference](https://noogle.dev/f/lib/fileset/toSource/).

Preserve the whole-source intent of `checks.python-quality`, treefmt, and the
Git hooks. They deliberately cover the repository and nested projects. A small
allowlist there could silently omit newly added code. Likewise, do not replace
the explicit secret-template fixture copies merely because a fileset is more
general. Source filtering must preserve the working directory layout and all
test fixtures.

`builtins.toJSON` plus `writeText` is already appropriate for simple generated
JSON, including [Actual](../modules/home/actual.nix) and
[native messaging manifests](../modules/home/browsers/shared/bitwarden-native-messaging.nix).
`pkgs.formats.json { }` matters more at an option boundary than as a mechanical
replacement for those lines. Actual already uses its `type` for `extraSettings`.
Consider the same JSON-compatible type for the untyped `types.attrs` policy
options in [chromium-policies.nix](../modules/shared/chromium-policies.nix),
checking both Linux JSON and Darwin plist consumers. This would change nested
merge/validation behavior; test combined definitions, lists, nulls, and invalid
values before adopting it. It is not a zero-risk spelling change.
[Pinned format implementation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/pkgs-lib/formats.nix).

Keep XML, CSS, PowerShell, and shell serialization separate. `toJSON` is not a
universal quoting function. In particular, the Windows installer renderer must
continue reading credentials at runtime and escaping XML then; generating secret
content with a Nix writer would put it in the store.

### Small library and package-composition improvements

| Local code | Function to use | Benefit and constraint |
| --- | --- | --- |
| `lib/browser/ublock.nix:3`, `modules/shared/chromium-policies.nix:67` | `lib.mapAttrsToList` and `lib.boolToString` | Replace attribute-name enumeration followed by lookup; preserve Boolean string encoding and sorted output. |
| `modules/shared/chromium-policies.nix:56`, `modules/home/browsers/shared/default.nix:86` | `lib.genAttrs` | Express extension-ID or MIME-name maps directly. Preserve `mkDefault` values and duplicate-name behavior. |
| `modules/home/wm/hyprland/default.nix:47`, line 84 | `lib.mod`, `lib.min`, `lib.max` | Remove duplicate arithmetic helpers. Preserve positive-resolution constraints and nearest-scale tie behavior. |
| `modules/home/desktop/wallpaper.nix:12`, `modules/home/shells/nushell/env.nix:5` | `lib.concatMapAttrsStringSep` | Simplify mapping followed by string joining. This does not fix or replace either target language's escaping. |
| `modules/home/macos/core-packages.nix:45` | `pkgs.linkFarm` | Describe exact `bin/<command>` symlinks without emitting `mkdir` and `ln` commands. Keep priority metadata and native absolute targets. |
| `modules/home/macos/core-packages.nix:58` | `writeShellScriptBin` plus an explicit aggregate | Remove hand-written shebang/permission construction if the extra derivations are worthwhile. Preserve native command paths and argument forwarding. |

Sources: [mapAttrsToList](https://noogle.dev/f/lib/attrsets/mapAttrsToList/),
[genAttrs](https://noogle.dev/f/lib/attrsets/genAttrs/),
[max](https://noogle.dev/f/lib/trivial/max/),
[pinned arithmetic helpers](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/lib/trivial.nix),
[concatMapAttrsStringSep](https://noogle.dev/f/lib/strings/concatMapAttrsStringSep/),
[linkFarm](https://noogle.dev/f/pkgs/linkFarm/).

Read-only probes confirmed equivalent pair encoding for Boolean, number, string,
and null values; duplicate-name behavior for the proposed `genAttrs` mapping;
and equivalent min/max results for a mixed integer/float fixture. No Darwin
wrapper migration or native execution was performed.

Keep the custom loader in [lib/default.nix](../lib/default.nix) unless its public
contract is deliberately redesigned. It excludes hidden/default files, produces
nested attribute sets, and uses a lazy fixed point for sibling exports. A flat
`listFilesRecursive` result does not express that behavior. Existing
`mapAttrs'`, `nameValuePair`, `mkIf`, `mkMerge`, `mkPackageOption`, and typed options
are already useful throughout the project. Host hardware policy, theme data,
browser rules, and runtime application logic need domain-specific improvements;
changing a Nix helper alone does not improve them.

## Findings for nixpkgs-personal

Reviewed: 2026-09-08. Repository: `nix-forge/nixpkgs-personal`, local `pkgs/` checkout at `5d62685c585aab9982b9b2ffbfe57b6abc3b587b` plus substantial pre-existing staged and unstaged changes. All local paths below are relative to that repository. Its Nixpkgs pin is `801bef6abd86b91e51083066b83fb354a11fc640`. Research only; no package/configuration edits.

### Package recommendation

The registry, platform selection, native package builders, signature handling, and several source filters already use appropriate Nixpkgs helpers. The best next work is to narrow the sources of development checks, add explicit collision detection to the Apple font aggregation, and use a checked shell writer for the update application. Python writers suit small standalone tools and extracted check programs. They are a poor replacement for the editable multi-file package updaters.

Noogle is a discovery index, not the compatibility authority. Its `writePython3` page displayed implementation text different from this repository's pinned source. Every proposed helper below was checked against the package repository's pin. Root integration uses a different Nixpkgs pin and needs its own evaluation.

### Package findings and sources

#### 1. Narrow development-check inputs with `lib.fileset.toSource`

Priority: medium. Local observations: `flake/dev/codex-desktop.nix:11` changes directory to the entire repository source; `flake/dev/packages.nix:24` passes the entire source to the unit-test runner. Consequently unrelated repository content participates in these derivations' source dependencies. The existing targeted fileset in `flake/dev/apple-fonts.nix:23` supplies a nearby example.

Use `lib.fileset.toSource` and `unions` around the actual check inputs. For the Codex updater suite, start with its package directory. For the generic unit-test runner, start with `tests/run-package-tests.py` plus `pkgs/by-name`; narrow further only after inventorying fixtures and imported helpers. `lib.fileset.fileFilter` can select Python files, but JSON catalogs, manifests, fonts.conf, and other fixtures must remain explicit inputs. The layout/independence check deliberately examines package directories, README presence, helper copies, and escaping symlinks, so retain that complete package view.

The helper selects files and provides a stable source name; `root` determines the resulting directory layout. Validate by comparing check derivation paths after an unrelated documentation edit versus a fixture edit in a temporary copied tree, then run the focused check. This is an expected dependency improvement, not a measured speedup.

Sources: [Noogle toSource](https://noogle.dev/f/lib/fileset/toSource/), [Noogle fileFilter](https://noogle.dev/f/lib/fileset/fileFilter/), [pinned fileset implementation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/lib/fileset/default.nix).

#### 2. Use `pkgs.buildEnv` where aggregation needs collision checking

Priority: medium. `pkgs/by-name/ap/apple-fonts/package.nix:133` combines selected assets using `symlinkJoin`. The proposed improvement is explicit duplicate-path policy, not a claim that the current catalog contains a conflict. `buildEnv` defaults to failing on differing collisions and permits matching contents/permissions when `checkCollisionContents` is true. The repository already uses it for font coexistence at `flake/dev/font-packaging.nix:5`.

Either migrate the aggregate or add a focused `buildEnv` check for its assets. Keep the existing `passthru` helpers and licensing/source provenance intact. A migration must preserve documentation and license files, rather than linking only `/share/fonts` in the actual published package. Put build controls such as `strictDeps`, `preferLocalBuild`, and `allowSubstitutes` in `derivationArgs` for the pinned `buildEnv` interface. Review package priorities and selected outputs, which `buildEnv` also interprets. Add a fixture with two different files under the same font path and prove rejection; verify the real aggregate has the intended file inventory and intact licensing.

Sources: [Noogle buildEnv](https://noogle.dev/f/pkgs/buildEnv/), [pinned buildEnv argument defaults](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/build-support/buildenv/default.nix#L34), [pinned symlinkJoin implementation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/build-support/trivial-builders/default.nix#L555).

#### 3. Prefer `writeShellApplication` for the repository update command

Priority: medium. `flake.nix:65` uses `replaceVarsWith` to resolve Bash, Git, and Python paths in `scripts/update-packages.sh`. This already pins the executables and rejects missing substitutions. `writeShellApplication` would additionally provide shell syntax checking, ShellCheck, strict Bash options, and declared runtime dependencies in one builder. Keep the script's existing editable-checkout discovery and argument forwarding.

`writeShellScriptBin` is appropriate for a small installed script needing a shebang and syntax check. It supplies neither runtime dependency PATH construction nor ShellCheck by itself. Use `writeShellApplication` for this command, with Git and Python runtime inputs, or keep `replaceVarsWith` and add an explicit check of the rendered script if preserving the current template interface matters more. Build the writer and test wrong-directory failure and `--help` in a disposable checkout; do not run a source-changing update as a packaging test.

Important exception: `flake/dev/git-hooks.nix:17` deliberately calls the host's installed Nix CLI to support its daemon/settings. A writer conversion must preserve that policy instead of injecting `pkgs.nix` or setting `inheritPath = false`. `writeShellApplication` permits `inheritPath` and `bashOptions` overrides at this pin. Do not replace existing `writeShellApplication` updater wrappers in Apple/Windows font packages with the less capable `writeShellScriptBin`.

Sources: [Noogle writeShellApplication](https://noogle.dev/f/pkgs/writeShellApplication/), [Noogle writeShellScriptBin](https://noogle.dev/f/pkgs/writeShellScriptBin/), [pinned implementations](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/build-support/trivial-builders/default.nix#L250).

#### 4. Use Python writers selectively; preserve package-local source layout

Priority: low to medium. Small Python programs currently embedded in `noctalia-dark-app-icons/package.nix:82`, `firefox-emoji/package.nix:64`, and `emojione-legacy/package.nix:69` could become local `.py` files invoked through `writers.writePython3`, with the necessary `libraries` declared. `writePython3Bin` is useful when the result should actually be installed under `bin/`; a check-only helper does not need a public executable name.

At this pin, the writer selects a Python interpreter with declared libraries and runs Flake8 by default. That check does not replace the repository's Ruff, type checks, or behavior tests. Confirm the chosen style rules agree instead of suppressing all checking. These existing checks already use `python3.withPackages`, so a writer is mostly a maintenance improvement, not a missing-dependency fix.

Do not pass each package's `update.py` to a standalone writer and assume equivalent behavior. Updaters find adjacent helpers and mutable pin files relative to `__file__`; a copied store executable changes that relationship and its files are immutable. Preserve repository-relative `passthru.updateScript` calls, with interpreter/runtime wrappers where needed. Likewise, `buildPythonApplication` becomes worthwhile if a reusable Python application actually acquires package metadata/modules/entry points. It adds little to a simple build-time script.

Sources: [Noogle writePython3](https://noogle.dev/f/pkgs/writers/writePython3/), [Noogle writePython3Bin](https://noogle.dev/f/pkgs/writers/writePython3Bin/), [pinned writer implementation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/build-support/writers/scripts.nix#L1178), local `docs/package-standard.md`, `tests/check-package-layout.py:85`.

#### 5. Keep discovery and platform helpers; simplify only incidental mapping

`pkgs/default.nix:6` already uses `lib.callPackageWith`, `packagesFromDirectoryRecursive`, and `mergeAttrsList`. This expresses the independent-package contract directly. Do not change it to a recursive personal scope: packages intentionally consume upstream dependencies, and the locally rebound `callPackage` also protects nested calls from overlay injection. Do not replace discovery with a hand-maintained attribute list.

`flake.nix:25` already filters through `lib.meta.availableOn`; that respects `meta.platforms` and `meta.badPlatforms`. The overlay discovers names outside its fixed point and intersects names into the incoming package scope. Retain this separation, which prevents recursion and leaves unsupported upstream overrides intact. Metadata availability does not prove successful builds on those platforms.

A low-risk cleanup at `flake.nix:49` is `nixpkgs.lib.genAttrs supportedSystems (system: import nixpkgs { ...; })` instead of `listToAttrs (map (system: { name = system; value = ...; }) supportedSystems)`. Compare resulting system names and selected derivation paths. This is readability work with low priority.

Sources: [Noogle discovery](https://noogle.dev/f/lib/packagesFromDirectoryRecursive/), [pinned directory traversal](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/lib/filesystem.nix#L370), [pinned callPackageWith](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/lib/customisation.nix#L267), [Noogle availableOn](https://noogle.dev/f/lib/meta/availableOn/), [Noogle genAttrs](https://noogle.dev/f/lib/genAttrs/).

#### 6. Preserve specialized native and binary package checks

The current native packages have behavior worth keeping. `finder-favorites/package.nix:98` runs its in-memory self-test and has installed-binary checks at line 127. `ocr-capture/package.nix:86` probes SDK support and preserves signing. `steam-cef-scale-override/package.nix:41` tests the C ABI interposition behavior with independent helper programs. Replacing these with trivial writers would lose useful builder and test behavior.

`pkgs.testers.testVersion` is suitable for an additional independently buildable passthru smoke test on a CLI such as Finder Favorites, using its `version` subcommand explicitly. It checks version presence, not the full current exact-line output, bundle signature, or runtime behavior. Do not substitute it for the existing stronger tests or call a GUI app just to get a version. A passthru test must also be included in flake checks/CI if automatic execution is required.

`testers.testEqualContents` can compare installed font inventories or old/new generated outputs during a migration. It uses diffoscope and checks metadata by default. Restrict comparison to intended content; avoid expecting entire wrapper trees or binaries with changed embedded store paths to remain byte-identical. Existing `cmp` checks are simpler for individual license files and need no replacement.

For prebuilt Darwin apps, preserve `stdenvNoCC`, `dontFixup`, copying of vendor signatures, and executable symlinks. For the Linux Codex package, retain `autoPatchelfHook`, `wrapGAppsHook3`, targeted runtime dependencies, and the shell wrapper's runtime Wayland expansion at `openai-codex-desktop/package.nix:222`. A generic binary-wrapper replacement would require preserving that shell evaluation.

Sources: [Noogle testVersion](https://noogle.dev/f/pkgs/testers/testVersion/), [pinned testVersion and testEqualContents](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/build-support/testers/default.nix#L54). Noogle's direct `testEqualContents` URL was unavailable during this retrieval; the pinned source was inspected directly.

### Package coverage

All 39 public package directories were inventoried, along with `flake.nix`, discovery, development partitions/checks/hooks, updater orchestration and package contract/layout checks. Detailed reading focused on concrete helper opportunities and platform-sensitive code.

| Area | Packages covered | Result |
| --- | --- | --- |
| Fonts and emoji | Apple catalog, eight standalone Apple developer-font packages, Apple Color Emoji, EmojiOne, Firefox emoji, Mutant Standard, Twemoji, Google Fonts, M PLUS, Windows fonts | Keep specialized archive/manifest/font tests; consider collision-checked aggregation and extracted Python checks. |
| Vendor/desktop applications | Bitwarden, Claude, LibreOffice, LinearMouse, Teams, Codex Desktop, remindctl, Spotify SpotX, Steam, T3 Code, Vorssaint, Wootility | Preserve platform-specific extraction/signature/wrapper behavior; avoid wholesale trivial-builder conversion. |
| First-party native utilities | Finder Favorites, OCR Capture, Steam CEF scale override | Keep native compilers, source sets and behavior checks. |
| Desktop assets and shell | Bibata, Noctalia dark icons, Noctalia personal | Existing standard derivations fit; Python check extraction is optional. |
| Agent skills | Anthropic, OpenAI, Matt Pocock, pstack | Keep reviewed catalogs, license selections and independent local helpers; no writer conversion of editable updaters. |
| Repository tooling | Public import/overlay, package discovery, three flake systems, partitions, checks, formatters/hooks, update app and CI selection | Prioritize source filtering and checked shell app; retain caller-supplied Nix and independence checks. |

### Package validation and limits

Ran read-only `nix flake metadata --json ./pkgs --no-write-lock-file`, resolved the exact Nixpkgs source, and ran a direct Nix evaluation against that pin. The evaluation enumerated all 39 registry entries, computed metadata-supported package names for `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`, and confirmed the proposed top-level builder namespaces/helpers exist. It succeeded. These are evaluations executed from Linux, not builds or native tests on those three systems.

No package build, formatter, unit suite, installation, GUI launch, source update, or deployment ran. The worktree was already dirty and was preserved. All performance, equivalence, and collision-fixture checks described above are proposed validation, not completed results.

## Findings for nix-config-framework and nix-seal

Reviewed: 2026-09-08. Scope: nix-config-framework at `db76717b9c7868d9df052114a1ee2168d3b51423` and nix-seal at `f76477bd8caac37f84553df48b48dc14a1365a9f`. Both worktrees were clean before and after research. Both standalone lockfiles pin nixpkgs `0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`; root integration uses a different pin. No configuration or implementation changed.

### Framework and secret-management recommendation

Prioritize correct systemd argument encoding in nix-seal, then replace duplicated credential grouping with `lib.groupBy`. Improve framework callback validation and discovery test diagnostics. Keep the existing fileset source boundary, Rust package builder, checked substitution, and explicit module discovery policy. Generic recursive discovery and blanket script-writer conversions would discard useful contracts.

The inventory covered the 18 tracked Nix files in nix-config-framework and 19 in nix-seal at the file-pattern level, with detailed source reading of discovery/composition, module options, platform activation, Rust packaging/source selection, generated metadata, tests, and development hooks. Rust crates, fuzzing, schemas and CI were inventoried to establish ownership; this was not a Rust, cryptographic, or vulnerability audit.

### Framework and secret-management findings and sources

#### 1. Encode systemd command arguments using systemd rules

Priority: high. Confidence: evaluated existing behavior; proposed remedy requires runtime tests.

[nix-seal Home Manager module](https://github.com/nix-forge/nix-seal/blob/f76477bd8caac37f84553df48b48dc14a1365a9f/nix/modules/home-manager.nix#L193) joins an argument list with spaces for `Service.ExecStart`. An evaluation fixture with the public dummy identity path `/run/keys/test identity%literal` produces `--identity /run/keys/test identity%literal --runtime-root %t/nix-seal`. The path passes existing option checks. The resulting command loses the argument boundary and exposes a literal percent to systemd specifier interpretation. The [NixOS module](https://github.com/nix-forge/nix-seal/blob/f76477bd8caac37f84553df48b48dc14a1365a9f/nix/modules/nixos.nix#L53) also constructs service commands with shell escaping, even though shell activation and systemd ExecStart use different parsers.

Noogle's [`lib.escapeShellArgs`](https://noogle.dev/f/lib/strings/escapeShellArgs/) is explicitly a Bourne-shell encoder. The relevant upstream counterpart is NixOS `utils.escapeSystemdExecArgs`, verified in [the pinned source](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/nixos/lib/utils.nix#L164). It quotes each argument and escapes literal dollars and percents. It is a NixOS utility, not a general `lib.escapeSystemdExecArgs` API. Noogle search found no indexed entry for it. Home Manager's pinned source includes the same logic locally in `modules/services/poweralertd.nix`.

Use the utility through NixOS's module `utils` argument for NixOS commands. Decide how to expose the same behavior to standalone Home Manager without assuming a NixOS module argument exists there. Crucially, the existing Home Manager `%t` runtime-root expansion is intentional. Encoding every argument as a literal would turn it into `%%t` and break runtime placement. Represent trusted specifier arguments separately, or use a reviewed command wrapper with an explicit runtime-root mechanism. Keep Darwin `ProgramArguments` as a list.

Validation needed: evaluation and runtime fixtures for spaces, quotes, dollar signs and literal percent in identity paths; successful intentional `%t` expansion; NixOS and Home Manager credential loading; dry activation; all activation phases. Treat this as a correctness recommendation, not a claim that a security exploit was demonstrated.

#### 2. Replace duplicated credential folds with `lib.groupBy` and `lib.mapAttrs`

Priority: medium. Confidence: pinned evaluation verified list order on an interleaved fixture.

The [NixOS credential fold](https://github.com/nix-forge/nix-seal/blob/f76477bd8caac37f84553df48b48dc14a1365a9f/nix/modules/nixos.nix#L58) and [Home Manager fold](https://github.com/nix-forge/nix-seal/blob/f76477bd8caac37f84553df48b48dc14a1365a9f/nix/modules/home-manager.nix#L35) reconstruct an attrset and append a singleton list per binding. They can share this expression:

```nix
bindings:
lib.mapAttrs (_: map (binding: "${binding.name}:${binding.path}")) (
  lib.groupBy (binding: lib.removeSuffix ".service" binding.unit) bindings
)
```

[`lib.groupBy` on Noogle](https://noogle.dev/f/lib/lists/groupBy/) and the [pinned implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/lists.nix#L1011) establish the grouping contract and builtin fast path. This names the operation directly and removes duplicated accumulation logic. No runtime speedup was measured. Preserve input order, duplicate-name assertions, `LoadCredential` merge priority and the systemd dependency graph. Do not deduplicate bindings as part of this replacement.

#### 3. Validate the framework callback while preserving its merge behavior

Priority: medium. Confidence: pinned module evaluation verified accepted function, rejected integer and rejected multiple definitions.

[`extraSpecialArgsFor`](https://github.com/nix-forge/nix-config-framework/blob/db76717b9c7868d9df052114a1ee2168d3b51423/flake-module.nix#L229) has `types.raw` despite being called as a function. `lib.types.addCheck lib.types.raw builtins.isFunction` rejects non-functions at the option boundary while retaining raw's single-definition merge behavior.

Sources: [Noogle addCheck](https://noogle.dev/f/lib/types/addCheck/), [pinned implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/types.nix#L1831), and [raw type](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/types.nix#L320). Noogle and the pinned docs warn about known `addCheck` behavior. The small evaluation covered this proposed raw/function use only; it does not resolve the general warning.

[`types.functionTo`](https://noogle.dev/f/lib/types/functionTo/) is an alternative only if combining multiple callback definitions is desired. Its implementation invokes definitions and merges returned values. That changes the present contract and is not a drop-in tightening. Also decide whether callable attrsets should be supported before broadening the predicate; current documented usage is an ordinary function.

#### 4. Give discovery tests named failures with `lib.runTests`

Priority: medium when extending discovery coverage. Confidence: source-backed; no test suite rewrite performed.

The framework's [tests/default.nix](https://github.com/nix-forge/nix-config-framework/blob/db76717b9c7868d9df052114a1ee2168d3b51423/tests/default.nix#L1) uses five bare assertions. [`lib.runTests`](https://noogle.dev/f/lib/debug/runTests/) returns named mismatches with expected and actual values, as confirmed by [pinned source](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/debug.nix#L512). It would make growing the policy fixtures easier to diagnose. Ensure the check fails when the returned list is nonempty; merely evaluating the list does not fail a build.

Useful cases are hidden/archive exclusion at every depth, missing optional roots, symlink treatment, directory `default.nix` precedence, hyphenated selector collisions, shared envelope selection, and deterministic import order. Existing integration checks for per-home arguments, Darwin shells and standalone-home suppression should remain.

#### 5. Check substituted shell output without removing checked substitution

Priority: medium as a focused validation improvement. Confidence: source-backed; no derivation built.

The runtime script at [nixos.nix:36](https://github.com/nix-forge/nix-seal/blob/f76477bd8caac37f84553df48b48dc14a1365a9f/nix/modules/nixos.nix#L36) and Python compile hook at [git-hooks.nix:7](https://github.com/nix-forge/nix-seal/blob/f76477bd8caac37f84553df48b48dc14a1365a9f/flake/dev/git-hooks.nix#L7) already use `replaceVarsWith`. That is a useful choice for versioned external scripts. [Noogle replaceVars](https://noogle.dev/f/pkgs/replaceVars/) describes strict replacement, and [pinned replaceVarsWith](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/replace-vars/replace-vars-with.nix#L53) confirms it fails unused or unexpanded placeholders.

Add Bash syntax and ShellCheck checks of the generated `$target` through `postCheck`, which the implementation invokes after placeholder validation. Do not override its forced `checkPhase`. Existing treefmt ShellCheck validates source templates; checking generated output additionally covers inserted shell snippets. [`writeShellApplication`](https://noogle.dev/f/pkgs/writeShellApplication/) is the comparison point for syntax checks and strict Bash defaults, but a replacement is not required to gain those checks. Preserve the runtime script's early `DRY_ACTIVATE` return and the hook's temporary bytecode directory cleanup.

### Framework and secret-management existing choices to retain

| Area | Finding |
| --- | --- |
| Framework discovery and selector collisions | Keep `lib/default.nix`'s explicit traversal and `uniqueAttrs` rejection. [`listFilesRecursive`](https://noogle.dev/f/lib/filesystem/listFilesRecursive/) includes nondirectory entries, traverses hidden/archive directories and assumes the root exists in the [pinned implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/filesystem.nix#L233). Generic attrset builders silently resolve duplicate keys. Neither preserves the discovery contract. |
| Rust source selection | `flake/rust-source.nix` already uses [`fileset.toSource`](https://noogle.dev/f/lib/fileset/toSource/), `unions` and `maybeMissing` to exclude metadata while including schemas, fixtures and Cargo inputs. Do not replace it with whole-repository source or a narrow `.rs` filter. |
| Rust packaging | `flake/production.nix:31` uses `rustPlatform.buildRustPackage`, Cargo locking and interop check dependencies. A shell or Python writer cannot replace the Rust protocol, crypto, policy or runtime implementations. |
| Public plan and activation JSON | `nix/lib/default.nix` deliberately closes top-level schema projection and hashes ciphertext. `shared.nix:454,490,502,769` already uses [`writeText`](https://noogle.dev/f/pkgs/writeText/) with serialized public metadata. Formatting helpers are not substitutes for schema validation, canonical hashing or private runtime paths. |
| Documentation package | `flake/production.nix:65` uses `runCommand` to run the built CLI, lint a manual and emit schemas/completions. Its multiple build steps justify a build command. Installing standard shell-completion locations is a separate packaging decision; the existing `share/nix-seal/completions` path may be a consumer contract. |
| Platform module composition | `mkIf`, `mkMerge`, `mkAfter`, `optionalAttrs`, typed submodules and Home Manager DAG entries already express policy and ordering. Broad attrset merges would not preserve module priority. Darwin command arrays already preserve argument boundaries. |
| Development shells and checks | `mkShellNoCC` is appropriate for tooling shells; Rust tooling is explicit in nix-seal. Upstream treefmt/pre-commit integration already owns formatter and hook behavior. Duplicate `nixfmt` in nix-seal's package list is minor cleanup, not grounds for a new abstraction. |
| Rust security implementation | Crates, fuzz fixtures, schema validation, signatures, cache/store trust and activation protocols require their own behavioral review. Noogle does not justify rewriting these in build-time Nix or shell. Follow nix-seal CONTRIBUTING for any later trust-boundary change. |

Low-value substitutions deliberately excluded from the priority list include changing every `listToAttrs` into `genAttrs`, shortening the 64-character bootstrap sentinel construction, and changing the stable sorting helper merely to remove a redundant sort. Grouped collision detection may be useful if measured selector scale warrants it; preserve which duplicate is reported and deterministic error text.

### Framework and secret-management validation and limits

Ran local evaluation on x86_64 Linux with the standalone pinned nixpkgs revision:

- Existing framework `tests/default.nix` returned `true`.
- Interleaved two-unit credential fixture returned identical old and proposed grouping, preserving `alpha = [ "a:/run/a" "c:/run/c" ]`.
- A real Home Manager configuration produced an unquoted identity argument containing a space and percent. Evaluation emitted the project's existing pre-1.0 and standalone-runtime warnings. No secret was read or decrypted.
- `evalModules` using the proposed checked-raw callback accepted a function, rejected an integer, and continued rejecting multiple callback definitions.

No package build, VM test, Darwin runtime check, deployment, secret operation or full Rust test suite ran. No implementation patch exists. Noogle was used to discover and compare functions; local pinned source was authoritative where the index differed or had no entry. Suggested implementation validation should run separately in each owning repository and include root integration with its own nixpkgs pin. Nix-seal requires its documented Cargo, cargo-vet and flake checks for implementation changes. No desktop closure build is necessary for this research.

### Framework and secret-management implication for the repositories

Make the systemd encoding follow-up concrete first, with a fixture preserving literal arguments and intentional `%t`. Then implement credential grouping and callback validation as separate, focused changes. Add discovery policy fixtures before changing traversal. Keep the source filtering, metadata and platform activation contracts explicit.

## Findings for ci, .github, and vpn-confinement

Reviewed: 2026-09-08. Question: which existing nixpkgs functions can replace maintenance code or improve reproducibility in `nix-forge/ci`, `nix-forge/.github`, and `nix-forge/vpn-confinement`?

### CI, community, and VPN recommendation

The strongest opportunities are packaging the shared validator as an executable with declared dependencies, replacing VPN confinement's internal hexadecimal arithmetic helpers, and using the Python writer for its diagnostics executable. The Python change requires formatting work: an isolated build of the current source fails the writer's default lint checks. Keep the VPN address validator and privileged CI queue action behavior intact. Their requirements exceed what a generic Nix function supplies.

This is a research inventory with focused probes, not an implementation or an exhaustive security review. No source checkout was modified.

### CI, community, and VPN revisions and coverage

| Repository | Reviewed commit | nixpkgs pin | Areas inspected |
| --- | --- | --- | --- |
| `nix-forge/ci` | `91464483eff23ba8501bb0c62bd20c1acf216b22` | `dc5d91f840324650bac8c379428c7037a416959a` | Flake, scripts, composite actions, workflow entry points, queue architecture, test inventory; full declared local check command |
| `nix-forge/.github` | `5d1bed48e903f1de7d3d96de1152ded29ade55f4` | No flake | Organization profile/readme, workflow/template inventory, CI and Nix template; shared workflow validator |
| `nix-forge/vpn-confinement` | `d3574be8604946076a38e74b88b39b022ad5ba84` | `8a37cfb926b31472f2e90b992c197c62d6bb4d74` | Module/library, diagnostics, lifecycle, firewall/policy, options/assertions, flake partition/check/docs/dev definitions, test inventory, selected tests and docs |

The VPN flake supports consumers choosing their own nixpkgs. The pinned source establishes compatibility for this snapshot, not every downstream pin. The community repository delegates to CI release commit `7903659c4b16378411a3ea79dd73cec5c82708cc`, while this investigation ran the newer reviewed CI HEAD. It does not prove that the older pinned release behaves identically.

Noogle was used to discover or inspect the functions below. Behavior was checked against the local store source for each repository's exact locked nixpkgs. Some Noogle URLs for `mod` and guessed conversion names were unavailable; the report uses the verified `lib.fromHexString` name and pinned primary source for `lib.trivial.mod`.

### CI, community, and VPN findings and sources

#### Package the shared workflow validator

Priority: medium, useful across all consumers.

Observed: [ci/flake.nix:10](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/flake.nix#L10) exports only development shells. [scripts/check-workflows.sh:3](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/scripts/check-workflows.sh#L3) derives its installation root from the script location and invokes `actionlint`, `zizmor`, `yamllint`, and Python from PATH. [actions/validate-workflows/action.yml:13](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/actions/validate-workflows/action.yml#L13) enters the shared flake's dev shell to run it.

Recommendation: expose a package such as `packages.<system>.validate-workflows` using `pkgs.writeShellApplication`, with runtime inputs for the three validators, required shell utilities, and a Python contract checker. Package [scripts/check-workflow-contracts.py:10](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/scripts/check-workflow-contracts.py#L10) with `pkgs.writers.writePython3Bin`, declaring `libraries = ps: [ ps.pyyaml ];`. This gives developers and the action the same runnable command and makes Python dependencies explicit. Existing `python3.withPackages` in the dev shell is already correct and should remain until all callers migrate.

The shell builder sets a runtime PATH, runs Bash syntax checking and ShellCheck, and defaults to `errexit`, `nounset`, and `pipefail`. Its default `inheritPath = true` still includes the caller's PATH. Use `inheritPath = false` only after declaring every required executable. The Python writer supplies the interpreter and can add dependencies, but also runs flake8 by default. [Noogle shell builder](https://noogle.dev/f/pkgs/writeShellApplication/), [Noogle Python writer](https://noogle.dev/f/pkgs/writers/writePython3/), [pinned shell source](https://github.com/NixOS/nixpkgs/blob/dc5d91f840324650bac8c379428c7037a416959a/pkgs/build-support/trivial-builders/default.nix#L268), [pinned Python source](https://github.com/NixOS/nixpkgs/blob/dc5d91f840324650bac8c379428c7037a416959a/pkgs/build-support/writers/scripts.nix#L1178).

Migration risk: passing the existing shell file unchanged to a writer would break the relative lookup for `.yamllint.yml` and the Python script because the executable moves into `/bin` in its store output. Embed an explicit configuration path and invoke the packaged checker. Preserve the caller-supplied target repository directory, workflow glob behavior, and composite-action interface. A store-backed executable does not make validation results cacheable when it inspects an arbitrary working directory. No measured speedup is claimed.

Tests: run the executable against CI, community templates and representative consuming repositories, with an empty or deliberately minimal PATH; preserve the 46 Python tests, shell lint, YAML checks, workflow contract checks, and action-interface tests. Test custom paths containing spaces.

#### Give the CI flake real check outputs

Priority: medium, paired with the validator package.

Observed: `ci` relies on [.github/workflows/ci.yml:25](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/.github/workflows/ci.yml#L25), which runs [scripts/check.sh](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/scripts/check.sh#L1) through `nix develop`. The flake exports no `checks`, so `nix flake check` does not express this project's test suite.

Recommendation: add an isolated `pkgs.runCommand` check that copies the required source, provides the full test dependencies including Git and Gitleaks, runs the existing script, and creates `$out` only on success. Reuse the package definitions in the development shell. Keep runtime scanning of a consumer's full Git history outside an immutable-source check; the secret-scan tests construct temporary repositories and should continue to test that behavior.

`runCommand` already uses `stdenvNoCC`; changing it to a manual derivation does not remove a compiler that was never required. [Noogle runCommand](https://noogle.dev/f/pkgs/runCommand/), [pinned source](https://github.com/NixOS/nixpkgs/blob/dc5d91f840324650bac8c379428c7037a416959a/pkgs/build-support/trivial-builders/default.nix).

Tests: build the new check on the three declared systems where supported. The local declared suite passed on x86_64-linux; the proposed sandboxed check has not been implemented or built.

#### Use the Python writer for VPN diagnostics

Priority: medium, direct replacement with a known migration gate.

Observed: [diagnostics.nix:74](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/modules/vpn-confinement/diagnostics.nix#L74) uses `writeTextFile` and manually supplies a destination, executable bit and Python shebang. The module substitutes five trusted manifest/tool paths into `doctor.py`.

Recommendation: keep that substitution and use `pkgs.writers.writePython3Bin "vpn-confinement-doctor" { } renderedSource`. It supplies the interpreter and `/bin` destination. Keep the explicit `ip`, `nft`, `wg`, and `systemctl` paths so diagnostics do not accidentally use host alternatives. [Noogle writePython3Bin](https://noogle.dev/f/pkgs/writers/writePython3Bin/), [pinned writer source](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/pkgs/build-support/writers/scripts.nix#L1178).

Observed migration failure: an isolated writer derivation using the existing, unsubstituted `doctor.py` failed flake8 with `E127` and `E501`. This probe verifies the default builder lint gate; it does not execute diagnostics. Format the source or adopt narrowly justified `flakeIgnore` settings while retaining the project's intended checks. Do not hide the failure by treating `doCheck = false` as a harmless default. Substitution can lengthen lines further, so build the fully substituted executable before acceptance.

Tests: the existing 15 doctor unit tests pass. Build the new executable, check its interpreter and dependency references, run `--help`, and rerun the diagnostics unit check plus runtime-policy/diagnostics coverage in a NixOS VM. The current unit tests load source code, so they do not independently establish correct executable packaging.

#### Replace hash arithmetic helpers with the library

Priority: medium, low implementation risk when restricted to current internal inputs.

Observed: [lib.nix:40](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/modules/vpn-confinement/lib.nix#L40) defines `intMod`, `stringChars`, a 16-branch hexadecimal digit decoder and `hexToInt`. Hexadecimal conversion is used for the first eight hex characters of internally generated SHA-256 hashes when deriving subnets and firewall marks.

Recommendation: use `lib.trivial.mod` and `lib.fromHexString` directly at those hash conversion sites. That removes the local string/digit helpers entirely. If `stringChars` remains useful for another purpose, `lib.stringToCharacters` has the same byte-oriented implementation. [Noogle fromHexString](https://noogle.dev/f/lib/fromHexString/), [Noogle stringToCharacters](https://noogle.dev/f/lib/stringToCharacters/), [pinned modulo source](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/lib/trivial.nix#L650), [pinned hexadecimal source](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/lib/trivial.nix#L1234), [pinned character source](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/lib/strings.nix#L955).

Compatibility: `fromHexString` returns an integer for these eight-character hash slices. It does not preserve the custom helper's `null` behavior on malformed text, and has its own accepted range and error behavior. Restrict the replacement to the proven internal input domain. The modulo formulas are identical for these nonnegative integers. Do not change subnet allocation or mark ranges during the refactor.

Validation: evaluated alternative formulas against the current exported subnet and mark functions for 256 deterministic names. All 256 subnet results and all 256 firewall marks matched. The current 28 evaluation regressions also returned true. This is sampled equivalence for the formulas, not a test of an edited module. Add fixed cases for zero and maximum eight-digit hex values and preserve existing long-name, collision, and endpoint-mark tests before merging.

#### Use shell quoting for shell diagnostics

Priority: medium, small correctness improvement.

Observed: [flake/checks.nix:170](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/flake/checks.nix#L170) emits a failure message using `echo ${builtins.toJSON message}`. JSON serialization is not a shell argument encoder.

Recommendation: use `printf '%s\n' ${lib.escapeShellArg message} >&2`. This preserves literal dollar signs, backticks, backslashes, quotes, and line breaks in assertion messages and avoids `echo` option handling. The current messages come from project evaluation checks; this research did not establish a reachable vulnerability or run an exploit. [Noogle escapeShellArg](https://noogle.dev/f/lib/escapeShellArg/), [pinned string helpers](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/lib/strings.nix).

Tests: deliberately fail the helper with multiline messages containing quotes, dollar signs, and backticks and compare stderr literally; then run rejection checks to ensure failures retain their messages. Keep `runCommand` for these checks so failures occur in the existing build-check interface.

#### Assess native options Markdown before keeping a second renderer

Priority: exploratory, requires rendered-site comparison.

Observed: [flake/docs.nix:42](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/flake/docs.nix#L42) already uses `pkgs.nixosOptionsDoc`, then [line 51](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/flake/docs.nix#L51) renders its JSON with roughly 100 lines of embedded Python. The renderer handles site frontmatter, declaration links and text wrapping.

Recommendation: prototype the existing `optionsDoc.optionsCommonMark` output with a small frontmatter wrapper and declaration-link transformation. The upstream builder exposes both JSON and CommonMark outputs. This may remove the custom handling of default/example values and preserve Markdown descriptions more faithfully, but it is not yet proven compatible with Astro/Starlight rendering. [Noogle nixosOptionsDoc](https://noogle.dev/f/pkgs/nixosOptionsDoc/), [pinned output documentation](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/nixos/lib/make-options-doc/default.nix#L12).

If the custom presentation is required, retain it and consider extracting the Python into a separate source file and `writers.writePython3` command called by `runCommand`. A Python writer creates an executable; it does not itself replace the derivation that runs the generator and produces Markdown.

Tests: compare every option, default, example, declaration URL and anchor; build the site; inspect rendered output. No CommonMark prototype or site build ran in this research.

#### Retain functions and abstractions that already fit

- VPN confinement already uses `pkgs.testers.runNixOSTest` for runtime checks and benchmarks, `nixosOptionsDoc` for evaluating options, `writeText` for immutable policy files, and the module library's submodules, `mkIf`, `mkMerge`, `mapAttrs'`, and typed ports. Keep these. A `writeShellScriptBin` wrapper around every systemd script would add packages without automatically improving its unit behavior. The systemd module already writes service scripts and the lifecycle code uses explicit store executables. [Runtime check wrapper](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/flake/checks.nix#L213), [policy files](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/modules/vpn-confinement/policy.nix#L18), [lifecycle script](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/modules/vpn-confinement/lifecycle.nix#L69).
- Do not substitute `lib.network.ipv6.fromString` for the security-sensitive boolean IPv6 validator. The pinned library explicitly omits IPv4-embedded IPv6 notation, whereas this project tests `::ffff:192.0.2.1`; it also defaults omitted prefixes and returns structured, expanded addresses. That is a different contract. Retain the custom parser until an alternative matches accepted and rejected input behavior. [Noogle IPv6 parser](https://noogle.dev/f/lib/network/ipv6/fromString/), [pinned limitations](https://github.com/NixOS/nixpkgs/blob/8a37cfb926b31472f2e90b992c197c62d6bb4d74/lib/network/default.nix#L16), [existing acceptance tests](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/flake/checks.nix#L391).
- Keep `writeText` plus `builtins.toJSON` for the diagnostics manifest unless typed module merging is needed. `pkgs.formats.json` would add another abstraction to an internal JSON value without a demonstrated benefit. This is a design judgment based on [the existing manifest](https://github.com/nix-forge/vpn-confinement/blob/d3574be8604946076a38e74b88b39b022ad5ba84/modules/vpn-confinement/diagnostics.nix#L13), not a claim of a defect in formats helpers.
- Keep the privileged queue reconciler's pinned action and API-only operation. It intentionally runs Python and GitHub CLI without a PR checkout. Forcing Nix setup and store evaluation into that job would expand prerequisites and require new trust and timeout analysis. Packaging a development CLI is separate from changing the privileged action. [Action entry point](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/actions/reconcile-queue/action.yml), [API-only script](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/scripts/reconcile-queue.py#L1), [documented trust requirements](https://github.com/nix-forge/ci/blob/91464483eff23ba8501bb0c62bd20c1acf216b22/docs/architecture.md).
- `.github` has no Nix implementation to replace. Its templates correctly call shared CI and leave package/check selection to each repository. Improve it through a reviewed shared-validator release and compatible template changes, rather than duplicating the package definitions here. Its public profile and onboarding prose gain nothing from a Nix function substitution. [Template](https://github.com/nix-forge/.github/blob/5d1bed48e903f1de7d3d96de1152ded29ade55f4/workflow-templates/nix-checks.yml), [ownership](https://github.com/nix-forge/.github/blob/5d1bed48e903f1de7d3d96de1152ded29ade55f4/README.md).

### CI, community, and VPN validation and limits

All commands ran on x86_64-linux with Nix 2.35.2, Determinate Nix 3.22.2. No deployment, GitHub write, system closure build, repository edit, or MCP installation occurred.

| Check | Result |
| --- | --- |
| CI ambient `python3 -m unittest discover -s tests -v` | Failed with two import errors because ambient Python lacked PyYAML. This was an environment mismatch, not a source regression. |
| CI `nix develop --command bash scripts/check.sh` using its lock | Passed workflow syntax/security/contracts, ShellCheck, Ruff checks/format, and all 46 Python tests. |
| Community files using the reviewed CI checkout's `scripts/check-workflows.sh` inside CI's dev shell | Passed. This used reviewed CI HEAD, not the community repository's older release pin. |
| VPN `python3 tests/eval/test_doctor.py` | All 15 tests passed. |
| VPN existing `tests/eval/regressions.nix` via locked nixpkgs | All 28 regression values true. |
| Alternative library hash formulas | 256 subnet results and 256 marks matched current exported functions. |
| Isolated `writePython3Bin` build of current doctor source | Failed default flake8 `E127` and `E501`. No runtime execution attempted. |

Not run: full VPN `nix flake check`, NixOS VM tests, benchmarks, aarch64 checks, Darwin CI checks, docs/site builds, proposed CI package/check builds, actual shell-escaping regression test, or live hosted workflow execution. The VPN TypeScript/Astro site, all VM test internals and every workflow body were inventoried or sampled for Nix relevance; they were not exhaustively audited. No quantitative performance claim follows from this work.

### CI, community, and VPN implication

Start with the two narrow VPN library/quoting changes and their focused regression checks. Package the shared CI validator next, preserving its current action interface. Adopt the diagnostics writer after its lint gate and installed executable checks pass. Treat the options Markdown change as a prototype requiring visible output review. These changes have specific benefits; the remaining project logic should retain its domain-specific functions until evidence supports a replacement.

## Repeatable Noogle research

Direct Noogle browsing and local locked-source inspection were sufficient for
this investigation. A new MCP installation was unnecessary. For repeated work,
`mcp-nixos` is a useful optional interface: its documented unified `nix` tool
supports `search`, `info`, and `browse` with `source="noogle"`, plus local
`flake-inputs` and explicit store-file access. The inspected upstream commit was
`6a517811658c21f97bd7703b35546085117fc310`.
[Upstream documentation](https://github.com/utensils/mcp-nixos/blob/6a517811658c21f97bd7703b35546085117fc310/README.md).

A future MCP-backed research session can use these tool arguments:

```text
nix(action="search", query="writePython3", source="noogle")
nix(action="info", query="pkgs.writeShellApplication", source="noogle")
nix(action="browse", query="lib.fileset", source="noogle")
nix(action="browse", query="lib.attrsets", source="noogle")
```

These are MCP calls, not Nix-language expressions or shell commands. The adapter
does not establish compatibility with a consumer's lockfile. Use this sequence
whether browsing directly or through MCP:

1. Identify the existing contract, owning repository, and actual call site.
2. Search Noogle by operation, such as grouping, source selection, script writing,
   argument escaping, option typing, package composition, or test comparison.
3. Inspect the implementation at that repository's locked Nixpkgs revision.
   Check argument defaults, platform limits, output layout, merge behavior,
   evaluation strictness, failure behavior, and runtime dependencies.
4. Prove equivalence on edge cases or identify the intended behavior change.
   Build generated scripts and exercise the installed command as well as its
   source-level tests.
5. Keep a replacement only when it reduces maintained logic, catches a real
   class of mistakes, or clarifies a contract. Record deliberate exceptions.

For reusable builders, a package-local helper may be enough. Introduce
`lib.extendMkDerivation` only when several builders actually need a shared,
overridable derivation interface. The root's unrelated host policies and the
package repository's independent updater contract are poor reasons to create a
single organization-wide wrapper.
[Noogle extendMkDerivation reference](https://noogle.dev/f/lib/extendMkDerivation/).

## Overall validation and implementation order

Completed on x86_64 Linux:

- Root shell prototype built with syntax checking and ShellCheck, then passed
  literal-path, dependency-PATH, copy-content, permission, and usage checks.
- Root Python prototype built with only E501 excluded, then passed an installed
  CLI fixture. The unchanged seed-renderer suite passed all eight tests.
- Root attribute/Boolean/min/max equivalence probes passed.
- Package discovery and metadata filtering evaluated on all three declared
  systems. This was Linux evaluation, not native builds on those systems.
- Framework tests, credential grouping, and callback-type probes evaluated
  successfully; the Home Manager argument fixture reproduced the identified
  command-rendering problem.
- The shared CI suite passed 46 tests and its declared checks inside the pinned
  development shell. Community workflow validation passed against reviewed CI
  HEAD, which differs from the community repository's release pin.
- VPN doctor tests passed 15 cases, evaluation regressions passed 28 cases, and
  512 sampled subnet/mark comparisons matched.

Retained failures are part of the evidence. The initial root Python writer
failed E501; the initial exported shell-value prototype failed SC2089/SC2090;
the VPN Python writer failed E127/E501; ambient CI tests failed without PyYAML.
The detailed sections explain which alternatives subsequently passed and which
remain unimplemented.

No complete desktop closure, Darwin runtime, VPN VM suite, docs site, or
organization-wide replacement patch was built. No configuration, lockfile,
package recipe, GitHub issue, workflow, MCP setting, or deployed system was
changed by this research. The deliverable is this reviewed report; temporary
prototypes and synthetic fixtures remain outside the repository.

The report passed the pinned Markdown linter, all 19 relative links resolved,
and its isolated publication scan passed the repository's Gitleaks policy.
Whitespace checks passed, and the report is not ignored by Git.

Implement the literal-argument fixes first, followed by individual writer
migrations and library substitutions. Keep each change in its owning repository,
run its focused checks, then validate root integration against the root lock.
Handle source filtering and font collisions separately because they change build
dependencies or aggregation behavior. Leave the options-document renderer as an
experiment until the generated site has been compared.

## Implementation follow-up

Implemented locally on 2026-09-08 after the research, across the six repositories
with actionable Nix changes. Existing unrelated work was preserved. No commit,
release, push, or system activation was performed.

| Repository | Implemented changes |
| --- | --- |
| nix-conf | Shell-escaped configurable paths; checked rendered Bash templates; wallpaper importer packaged with `writeShellApplication`; Windows seed and Codex appearance Python writers; literal systemd video arguments; JSON-compatible policy option types that retain an attribute-set root; focused Rust source fileset; attribute, arithmetic, MIME and macOS command-composition helpers. |
| nixpkgs-personal | Focused updater/unit-check filesets; checked update application; `genAttrs` system exports; collision-checked font aggregate; standalone Python asset checks with retained behavioral assertions and type checking. |
| nix-config-framework | Function-valued callback validation; named `runTests` failures; hidden-file, archive, symlink, default-precedence, collision and callback regression fixtures. |
| nix-seal | Systemd literal argument encoding with intentional standalone `%t` preserved; shared credential grouping; rendered Bash checks; evaluation and real systemd regression tests; [ADR 0016](../nix-seal/docs/adr/0016-systemd-literal-arguments.md). |
| vpn-confinement | `mod` and `fromHexString` replacements with fixed subnet/mark vectors; packaged Python doctor; safe diagnostic-message quoting; native CommonMark options renderer and regenerated reference. |
| ci | Packaged workflow validator and Python contracts, explicit tools and policy paths, sandboxed validation check, composite-action integration and a portable test interpreter. |
| .github | Retained its shared-CI delegation. Its templates passed the newly packaged validator. |

The native VPN documentation experiment passed its compatibility gate and was
implemented. Both site versions preserved all 43 options, defaults and declaration
links, four examples, 44 heading anchors and 48 rendered code blocks. The final
site build produced 21 pages. Its generated Markdown is excluded from the prose
formatter so subsequent regeneration remains faithful to `nixosOptionsDoc`.

The changes retain the research's explicit keep decisions: custom discovery,
activation ordering, whole-repository quality scans, native builders, signing,
license evidence, editable multi-file updaters and stronger existing binary tests.
Optional `testVersion` and `testEqualContents` probes were not added where existing
checks already prove more. New font fixtures use `testBuildFailure` to verify
conflicting content is rejected; identical duplicates build successfully.

Validation completed on x86_64 Linux:

- Built the full desktop system closure on the desktop host without activation.
  Root integration used the then-current locked Nixpkgs revision
  `0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`.
- Built the actual configured desktop, VM and Codex appearance helpers, and ran
  the root browser, desktop and virtualisation configuration contracts.
- Passed policy merge/type checks and wallpaper tests with spaces, an apostrophe,
  percent and dollar signs, an empty caller PATH, and file/directory permissions.
- Passed 13 virtualisation tests and eight tests against the packaged Codex
  appearance wrapper.
- Passed framework and nix-seal full flake checks, including both nix-seal VMs,
  formatting and hooks. Rust formatting, Clippy, workspace tests and Cargo Vet
  also passed for nix-seal.
- Passed package `just check`, `just lint`, `just test`, focused updater checks,
  the four changed asset/font package builds and both font collision fixtures.
- Passed CI validation and minimal-PATH runs against CI and organization templates.
  The update application passed minimal-PATH argument forwarding and wrong-checkout
  rejection fixtures.
- Passed all VPN flake checks, including runtime VMs, and the final production
  documentation site build.

Root-wide evaluation still reports one unrelated `secret-templates` expectation
mismatch during the ongoing secret-template migration. The rest of that evaluation,
including the added checks, completes. Validation used a temporary source snapshot
containing tracked and non-ignored untracked project files, including the pending
ciphertexts, without changing the user's Git staging. Ignored local evidence and
caches were excluded from the snapshot.

Darwin configurations and helper derivations were evaluated. Native macOS wrapper
and Rust-helper build/runtime validation remains outstanding because the Linux
host has no Darwin builder. The attempted wrapper build reports a platform
mismatch. Shared-CI consumer pins remain at their existing releases; publication
and consumer rollout were not part of these local changes.

## Second investigation, 2026-09-08

This investigation starts after the implementation follow-up above. Its question
is which useful replacements or fixes remain in the current working trees.
Earlier build results remain historical evidence; they are not new validation
for this pass. The organization API still returned the same seven repositories.

### Answer and newly identified gaps

Fix the remaining string-encoding boundaries and shallow option merges before
adding more builder abstractions. The earlier writer, fileset, font-collision,
and VPN arithmetic changes are already present. Repeating those migrations
would add no benefit.

| Component | New finding | Recommended change |
| --- | --- | --- |
| Actual and Ironbar user services | Actual uses shell quoting for its configuration path; Ironbar interpolates XDG paths directly into `ExecStart`. Both accept configurable paths. | Use the existing systemd argument utility, with each executable, flag, and path as a separate argument. |
| LibreOffice profile helper | The Bash template encloses the raw profile placeholder in single quotes. A profile containing an apostrophe makes the rendered script invalid. | Apply `escapeShellArg` to the value, remove the template's surrounding quotes, and check the rendered script. |
| Ironbar configuration | Raw icon-theme and network-command placeholders appear inside TOML string quotes. Quotes and backslashes can make the configuration invalid. | Replace complete string tokens with `builtins.toJSON` output and verify parsed values. A larger native-TOML rewrite is unnecessary for these two string fields. |
| Framework selector discovery | The implementation sorts already sorted attribute names and repeatedly filters the complete selector list to find duplicate names. | Use `attrNames` directly and group selectors once. Search the original name list for the first duplicate to retain diagnostic order. |
| macOS custom preferences | `types.attrs` merges only the outer attribute set, so separate definitions within one preference domain lose settings. | Use nested attribute sets with the existing plist value type, then test multiple contributors and scalar conflicts. |
| Browser policy options | The configurable Gecko policy and resolver-policy options still use `types.attrs`; the earlier typed merge change covered Chromium. | Evaluate JSON-compatible option types with regression cases for nested policy contributions. Keep existing policy ownership and precedence explicit. |
| Shared CI discovery | Both shell and Python discovery omit `action.yaml`, although GitHub supports that metadata name. | Include both metadata extensions and test alternate names through the packaged validator. |

The remaining LanguageTool `ExecStart` also uses shell quoting. Its current
arguments are store paths, constants, and a numeric port, so changing it to the
systemd helper is consistency work; the inspected argument list does not
reproduce the configurable-path failures above.

### Sources and compatibility

The effective root Nixpkgs input resolves to
`0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`. Reading only
`nodes.nixpkgs.locked.rev` from the lockfile gives a different node in this
working tree. The compatibility check used the actual resolved flake input and
its store source. This distinction matters when inputs use `follows`.

`escapeShellArg` targets a Bourne shell. The pinned systemd utility additionally
encodes literal percent and dollar signs and quotes complete arguments. Keep
intentional systemd specifiers separate from literal user data. The utility
lives in `nixos/lib/utils.nix`, rather than the general `lib` namespace.
[Noogle shell-quoting contract](https://noogle.dev/f/lib/strings/escapeShellArg/),
[pinned systemd utility](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/nixos/lib/utils.nix#L165),
[systemd command-line specification](https://github.com/systemd/systemd/blob/v259/man/systemd.service.xml).

Nix guarantees alphabetical ordering for `attrNames`. The locked `lib.groupBy`
uses the evaluator's builtin when available. Grouping by `.name` does not need
to evaluate a selector's `.value`. Preserve the framework's explicit collision
error and its custom discovery rules, rather than letting `listToAttrs` choose
one entry silently.
[Nix builtin reference](https://nix.dev/manual/nix/2.35/language/builtins.html#builtins-attrNames),
[Noogle grouping reference](https://noogle.dev/f/lib/lists/groupBy/),
[pinned grouping implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/lists.nix#L1031).

The pinned `types.attrs` implementation folds definitions with `//`. It cannot
combine nested contributions. `attrsOf` delegates merging to its element type;
JSON and plist format types supply recursive value types. Changing an option's
type also changes conflict and list-merging behavior, so a blanket replacement
of every `types.attrs` is inappropriate. Framework special arguments and
read-only exported data need their own contracts.
[Pinned option types](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/lib/types.nix#L596),
[pinned JSON, TOML, and plist formats](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/pkgs-lib/formats.nix),
[module definition merging](https://nixos.org/manual/nixos/unstable/#sec-option-definitions-merging).

The Ironbar fix can retain the current template. The test below establishes that
the Nix JSON encoder produces TOML-compatible tokens for the tested strings.
This is a claim about those encoders and fixtures, not a claim that arbitrary
JSON documents are TOML documents. For a structured configuration assembled
from many values, `pkgs.formats.toml.generate` remains the supported builder.
[Nix JSON encoding](https://nix.dev/manual/nix/2.35/language/builtins.html#builtins-toJSON),
[pinned TOML builder](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/pkgs-lib/formats.nix#L476).

GitHub supports `action.yml` and `action.yaml`. The omission exists in both
`scripts/check-workflows.sh` and `scripts/check-workflow-contracts.py` in the
inspected shared-CI working tree. A package wrapping those scripts does not
correct their input discovery.
[GitHub metadata reference](https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax).

### Organization-wide choices retained

The package repository already uses focused filesets, `meta.availableOn`,
checked Python writers, and collision-checked font composition. Nix-seal already
uses a Rust-specific fileset containing Cargo metadata, schemas, fixtures, and
optional Cargo configuration. Keep those sources tied to actual build inputs.
A fileset with an explicit root controls the resulting directory layout; its
file selection controls which changes affect the source store path.
[Noogle fileset contract](https://noogle.dev/f/lib/fileset/toSource/).

Keep shared CI's complete source validation and the community repository's
delegation to it. Narrowing a whole-repository linter to a handpicked fileset
would omit future files. Keep VPN's specialized address validators and runtime
VM tests; `mod`, `fromHexString`, and the diagnostics writer have already replaced
the straightforward library and builder duplication. Package-build tests,
configuration evaluation, and VM runtime checks answer different questions.
No new generic builder replacement was justified in those areas by this pass.

### New validation and limits

The research probes ran on x86_64 Linux with the effective root Nixpkgs input
identified above:

- The original Ironbar template parsed with ordinary strings. Substituting a
  double quote or a backslash into its raw placeholders made `tomllib` reject it.
- Five string fixtures round-tripped through Nix `builtins.toJSON` and Python
  `tomllib`, covering quotes, backslashes, newline, tab, carriage return,
  backspace, form feed, U+001F, and Japanese text. An attempted NUL fixture was
  rejected by Nix's JSON input decoder before reaching the TOML test.
- Rendering the original LibreOffice template with an apostrophe-containing
  profile made `bash -n` return 2.
- An isolated module evaluation with two contributions under one domain lost
  one contribution with `types.attrs`. Both nested plist and JSON option types
  preserved the two independent keys.
- A grouping probe returned the expected counts for repeated names without
  evaluating deliberately throwing payload values.

These are focused research probes, not implementation acceptance checks. This
section does not claim a new desktop build, Darwin runtime check, VPN VM run,
or complete CI build. The implementation work must record its own before-and-after
tests, repository checks, and outstanding platform limits.

### Second implementation follow-up

The second pass implemented additional changes in the root, framework, and CI
working trees. It preserved the earlier implementation and unrelated pending
work. The organization inventory still contains seven repositories.

- Actual and Ironbar encode complete systemd argument lists with the pinned
  `escapeSystemdExecArgs` utility. LanguageTool uses the same utility for its
  existing store-path and numeric arguments.
- Ironbar's two configurable TOML strings now use encoded string tokens.
- LibreOffice shell-escapes its profile path and checks its rendered command
  with Bash and ShellCheck. A local SC2016 annotation documents that dollar
  signs in that path are literal.
- macOS custom preferences reuse the corresponding nix-darwin option types.
  Independent contributions within one domain now merge recursively; conflicting
  scalar definitions and function values fail evaluation.
- Framework discovery uses `attrNames` ordering and `groupBy` for duplicate
  selector detection. The existing first-duplicate diagnostic and traversal
  behavior remain intact. No benchmark claim accompanies this simplification.
- Shared CI discovers both action metadata extensions in its supported action
  directories. Repositories containing only composite actions skip actionlint
  and still run action validation and contract checks.

The root regression checks live in [the Nix fixtures](../tests/nix/noogle.nix).
Before the fixes, the systemd VM showed `%n` expanding into the service name
inside Actual's path, Ironbar's configuration failed TOML parsing, LibreOffice's
wrapper failed shell parsing, and the macOS merge assertion failed. CI's new
tests demonstrated that both `action.yaml` locations escaped contract validation.
The fixtures pass after the changes. The final path fixtures also include
quotes, a backslash, and a literal `${HOME}` expression.

Validation performed on x86_64 Linux:

| Scope | Result |
| --- | --- |
| New root regression checks | Real systemd VM, Ironbar TOML parsing, LibreOffice profile update, and macOS preference merge/type assertions passed. |
| Existing focused root checks | Platform contracts, desktop command regressions, and JSON policy checks passed. |
| Desktop integration | Complete system closure built on the desktop host; no activation. |
| Framework | Full local flake checks passed, including discovery, formatting, and hooks. |
| Shared CI | Full local flake check passed, including 48 Python tests and declared linters. |
| Packaged CI validator | Passed community templates and a composite-only `action.yaml` fixture; rejected a mutable action reference. The fixture used an empty caller PATH. |
| Package repository | `just check` passed evaluation across all declared systems; `just test` passed package independence, policy, and unit-test targets on Linux. |
| Nix-seal and VPN | Local flake checks passed using existing cached results, including their VM checks. No fresh VM execution is claimed for these two repositories. |

The broad root evaluation reproduced the existing `secret-templates` mismatch
between the expected legacy `nix-access-tokens` attribute and the migrated empty
attribute set. That evaluation was then stopped to reduce concurrent memory use;
it is not a clean full-root check result. The focused checks and system build
above completed separately. Native Darwin builds and activation remain untested.

Gecko policy merging remains a research recommendation because its resolver
override and list precedence need an explicit compatibility fixture. No new
replacement was justified for the already improved package builders, nix-seal
implementation, VPN parsers, or community delegation. Changes remain local;
shared-CI release pins and deployed systems were not updated.

### Completion follow-up

This pass closes the Gecko merge recommendation and investigates the build
failures found while validating the pending generated-configuration migration.
The earlier validation limits describe earlier runs; the results below supersede
them for the named checks.

Gecko policies and system-resolver policies now use an attribute set of JSON
values. The regression fixture evaluates the real Firefox and Zen adapters.
It checks nested contributions, ordered policy lists, invalid values, scalar
conflicts, and the adapters' existing resolver and extension precedence. The
old option type failed the merge assertion; the new type passes it.

The default-browser and Colima forwarding helpers now shell-escape complete
values before substitution. Both generated helpers have Bash and ShellCheck
build checks. Local probes covered apostrophes, double quotes, backslashes, and
literal shell-variable syntax. Their original assignments either failed parsing
or changed the values; the revised assignments preserve them.

The native-configuration migration also exposed three integration constraints:

- Helper Nix expressions belong outside auto-imported module trees. Four
  desktop configuration data files now live under [the desktop modules](../modules/home/desktop).
  Keeping them under `modules/home` made discovery call them as modules and
  fail on unexpected arguments.
- Each generated setting needs one owner. The custom Noctalia module derives
  its palette, font, and settings from Stylix, so it disables Stylix's competing
  Noctalia adapter. Otherwise the two modules define conflicting notification
  opacity and palette names.
- Calling a format's `generate` function directly does not apply its module
  option type's coercions. LanguageTool's positive integer options now pass
  through `mapAttrs (_: toString)` before Java-properties generation. A native
  build previously failed when the generator sent numbers to jq string
  operations. The regression reads the generated properties selected by the
  service command and verifies four nondefault numeric values.

The coercion behavior follows the pinned
[Java-properties implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/pkgs-lib/formats/java-properties/default.nix).
The conversion preserves attribute names using
[Noogle's `mapAttrs` contract](https://noogle.dev/f/lib/attrsets/mapAttrs/).

#### Native filesystem-notification failures

Native builds exposed failures in deploy-rs's immediate-confirmation test and
Prism Launcher's resource-folder watcher test. A small FSEvents reproduction
could not start a stream in the strict Nix sandbox. Adding only permission to
look up `com.apple.FSEvents` made it observe immediate file removal.

The initial package overrides appended that permission while retaining upstream
tests. This was the same permission used by the pinned
[Nixpkgs watchfiles package](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/development/python-modules/watchfiles/default.nix#L38).
Nix rejects package-specific sandbox profiles in strict mode. That first pass
therefore selected relaxed mode for Darwin, which also permits upstream
fixed-output and `__noChroot` exceptions. This choice was subsequently reverted
in the [strict-sandbox follow-up](#strict-sandbox-follow-up). See the
[Nix sandbox setting](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html#conf-sandbox).
The earlier native validation used a command-level relaxed setting with
`--max-jobs 1 --cores 2 --option eval-cores 1`. It did not change the running
daemon's configuration, and relaxed mode is no longer the configured policy.

The deploy-rs package rebuilt successfully with all eight tests enabled. Its
confirmation test changed from a timeout to a pass in 0.03 seconds. No source
patch, increased timeout, or rollback-policy change was needed.
Prism Launcher also rebuilt successfully with all 21 tests passing; its
resource-folder watcher test passed in 0.75 seconds.

#### Validation of this pass

All 47 declared x86_64-linux root checks passed. They ran in separate evaluation
processes because retaining all fixtures in one `nix flake check` process caused
sustained memory pressure under the configured workload limit. The combined
invocation was stopped; this is a complete pass of the declared checks, not a
claim that the combined invocation completed. The only hook failure was a new
script template's missing executable bit; the corrected hooks passed. The
LanguageTool properties regression and service-command test also passed after
the final fixture change.

Ten native aarch64-darwin helper and runtime checks passed: Rust secure-file
helpers, macOS home helpers and dry-run behavior, browser helpers, generated
activation fixtures, and preparation, environment, database, and private-path
validation. The generated-activation check uses temporary fixtures; no system
or user profile was activated. The formerly failing root secret-template check
also passed with the concurrent migration's updated contract.
The native nix-seal package built with 190 Rust tests passing and none ignored.

The complete desktop system closure built successfully on its native Linux
host after these changes, including the generated Noctalia configuration. The
build did not activate the system.

The complete aarch64-darwin system closure also built successfully, including
Home Manager, the native helpers, the corrected LanguageTool properties, and
the patched deploy-rs and Prism Launcher packages. Both system builds used
temporary source snapshots containing tracked and non-ignored untracked source
files and the working submodules. Ignored captures and caches were excluded.
The build results cover the tested snapshots; concurrent edits and live-system
activation are separate from that evidence. No deployment, activation, commit,
or push was performed in this pass.

### Strict-sandbox follow-up

Linux, Darwin, and standalone Home Manager configurations retain
`sandbox = true` and `sandbox-fallback = false`. The two Darwin package-specific
FSEvents sandbox profiles have been removed. Platform regression checks now
assert the strict daemon and standalone-client settings.

The build sandbox deliberately denies the host FSEvents service. Preserve that
boundary and the applications' production watchers by limiting the change to
their integration tests:

- The Darwin deploy-rs package excludes only
  `tests::confirmation_watcher_observes_immediate_canary_removal` through its
  test flags. The other tests remain enabled. The excluded test still exists
  unchanged in the source for native integration testing.
- A Darwin-only Prism Launcher test patch probes whether a temporary directory
  can be watched. If the host rejects the watch, `test_removeResource` reports
  `QSKIP`. The other cases still run. Where native watches work, the test runs
  its original assertions. The patch does not change application code.

Qt supports explicit skip results for unavailable test prerequisites. Its
[file-watcher contract](https://doc.qt.io/qt-6/qfilesystemwatcher.html#addPath)
reports watch-setup failure through `addPath`, and its
[test documentation](https://doc.qt.io/qt-6/qtest.html#QSKIP) distinguishes skipped
tests from passes. The prior native runs above passed both FSEvents integration
tests. Those results remain historical evidence; the strict sandbox build does
not claim to execute those two cases.

The strict deploy-rs build passed seven tests and filtered only the named
FSEvents integration test. Prism Launcher built successfully with all 21 CTest
groups passing; the capability guard above permits the unavailable watcher case
to skip within its group. The platform policy assertions and repository hooks
passed. The native client's effective Nix configuration also reported
`sandbox = true`; no daemon configuration was changed during validation.

The complete native Darwin system closure then built successfully with explicit
`sandbox = true`, one build job, and two build cores. This verifies system
assembly with the strict package fixes. The build did not activate the system.
