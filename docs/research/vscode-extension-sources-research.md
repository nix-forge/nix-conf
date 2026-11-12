# VS Code extension sources and dependency ownership

Reviewed: 2026-11-09. Scope: root Nixpkgs revision
`02c087f3fe673c9e317f206a627cb6b910336dbe`, nix4vscode revision
`c06b9236b78dde9a0db7ae1ceeae587b374221c6`, and comparison-only
nix-vscode-extensions revision `934620178cf8eed2058484c24b5db62dbf4f08b1`.

## Answer

Choose the source per extension's actual packaging requirements. Use a curated
Nixpkgs recipe where its repairs matter and its version is suitable; use a
catalog for fresher clients or extensions missing from Nixpkgs. Keep stable,
editor-compatible releases and the correct execution platform as defaults.
Separate package construction from editor configuration and project environments.
This recommendation follows inspection of source recipes; it does not certify
all packages from either source.

## Source selection

| Source | Best use | Important limit |
| --- | --- | --- |
| `pkgs.vscode-extensions` | A suitable version with useful native, immutable-store, helper-script, or runtime integration | Recipes differ: some contain substantial repairs, others only fetch a VSIX; inspect the selected recipe |
| Existing `inputs.nix4vscode` | Fresh or historical compatible VSIX versions, with explicit per-extension adaptations | Does not automatically reuse Nixpkgs extension recipes |
| Alternative `nix-vscode-extensions` | A broad recent catalog with Nixpkgs recipe reuse and special handlers | Reusing a recipe against newer VSIX content still needs validation; latest-only caches may lack older compatible releases |

At the inspected pin, nix4vscode applies the first available decorator source:
external attributes, a specially named package override, or a local decorator.
Only cpptools and Lua have local decorator files. Its builder is derived from
Nixpkgs machinery, but this does not import every curated extension repair.
External decorator lists and hook strings replace matching attributes rather
than automatically appending to them. See the pinned
[construction code](https://github.com/nix-community/nix4vscode/blob/c06b9236b78dde9a0db7ae1ceeae587b374221c6/nix/extensionsFromInfo.nix).

Concrete comparisons from this configuration's Nixpkgs pin:

- **Jupyter:** both sources offer 2025.9.1. The Nixpkgs recipe adds package
  metadata and writable temporary storage for immutable installation. The notebook module now selects this curated package and checks its
  minimum editor version. Kernel execution still needs a project environment
  and a separate runtime test. This inspection does not establish that the current raw VSIX fails.
  [Jupyter recipe](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/applications/editors/vscode/extensions/ms-toolsai.jupyter/default.nix).
- **Python:** Nixpkgs offers 2026.4.0 with helper-library replacement and script
  patching; the catalog offers 2026.10.0. Choosing requires an explicit tradeoff
  between those repairs and newer functionality. Do not blindly transplant old
  patches onto the newer layout.
  [Python recipe](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/applications/editors/vscode/extensions/ms-python.python/default.nix).
- **Rust:** the pinned Nixpkgs client is older and patches its default server
  path. The catalog client plus this repository's explicit Nix server path is a
  reasonable alternative, with client/server behavior tested separately.
  [Rust recipe](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/applications/editors/vscode/extensions/rust-lang.rust-analyzer/default.nix).
- **Copilot Chat:** the selected Nixpkgs recipe is a simple VSIX wrapper at this
  pin. Keeping it is reasonable, but it is not evidence of special native fixes.
  [Copilot recipe](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/applications/editors/vscode/extensions/github.copilot-chat/default.nix).

Avoid an automatic rule that prefers Nixpkgs whenever an attribute exists:
adding a new upstream attribute could otherwise silently change an extension's
source and version. Record meaningful source exceptions beside their owner.
Use one catalog unless a demonstrated requirement justifies another input.

## Editor package variants

Keep `pkgs.vscode` with Home Manager's profiles for this setup: the module owns
extensions, settings, and platform launch integration. `pkgs.vscode-with-extensions`
is useful for a self-contained package when Home Manager is not the extension
owner; its wrapper supplies its own `--extensions-dir`, so avoid two competing
extension-directory owners.
[Pinned wrapper](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/applications/editors/vscode/with-extensions.nix).

On Linux, `pkgs.vscode.fhs` (`vscode-fhs`) and `fhsWithPackages` provide a broader
compatibility environment for foreign binaries expecting conventional libraries
and paths. Reserve that option for an identified requirement rather than using
it to avoid declaring dependencies. It does not replace project dependency
pinning or extension configuration, and it is not the macOS setup.
[Pinned implementation](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/applications/editors/vscode/generic.nix).

VSCodium is a different editor-product choice; review registry availability and
extension licensing before changing to it. Keep stable editor/client channels
as the default, with prereleases confined to a specific tested need.

## Variants and compatibility

For this repository's Microsoft VS Code installation, use nix4vscode's stable
`forVscodeVersion actualEditorVersion`. Its shorter `forVscode` entry point uses
its own package set's default VS Code version, which can differ from a custom
`programs.vscode.package`. An identifier suffix such as
`publisher.extension.1.2.3` requests a version present in the locked catalog.
Prerelease functions permit prereleases; they do not require one. Open VSX
functions select a different registry whose publisher, availability, and license
must be checked separately. See the pinned
[selection implementation](https://github.com/nix-community/nix4vscode/blob/c06b9236b78dde9a0db7ae1ceeae587b374221c6/nix/forVscodeVersionRaw.nix).

For nix-vscode-extensions, the comparable selection is
`(catalog.forVSCodeVersion actualEditorVersion).vscode-marketplace-release`.
The unsuffixed Marketplace set admits prereleases; `*-release-universal`
restricts selection to universal stable artifacts. Allow platform-specific
artifacts normally. Its cache stores recent channel/platform candidates rather
than complete historical versions, so compatibility filtering may find no
candidate for an older editor. Its Nixpkgs recipe-reuse machinery is a useful
option, not a guarantee that every reused patch fits a newer client.
[Variants](https://github.com/nix-community/nix-vscode-extensions/blob/934620178cf8eed2058484c24b5db62dbf4f08b1/README.md),
[recipe reuse](https://github.com/nix-community/nix-vscode-extensions/blob/934620178cf8eed2058484c24b5db62dbf4f08b1/nix/mkExtension.nix).

A universal VSIX can still contain native code. Select for the machine running
the extension host; the remote workspace host can differ from the local UI host.
Declared editor-engine compatibility does not prove native-library or protocol
compatibility. [Extension hosts](https://code.visualstudio.com/api/advanced-topics/extension-host).

## Where dependencies belong

| Dependency | Owner and mechanism |
| --- | --- |
| Another required extension | Explicitly include its `extensionDependencies` closure in the declarative extension list |
| Optional extension-pack member | Select only the wanted `extensionPack` members; do not automatically install every recommendation |
| Editor language server, formatter, debugger executable | Owning language module selects a Nix package and configures the extension's executable path |
| Project compiler, interpreter, libraries, kernel | Project flake/dev shell, dependency lockfiles, and selected environment |
| Tools executed while packaging | Recipe `nativeBuildInputs`, such as jq, patching hooks, and wrapper tools |
| Native runtime libraries | Recipe dependencies plus actual linker/RPATH/interpreter or loader integration |
| Runtime executable without a configurable path | A targeted wrapper or reviewed invocation patch in its package recipe |

Extension dependencies and packs are distinct from npm dependencies inside a
VSIX. Nix catalogs do not imply recursive manifest installation. For example,
Python's Pylance member is a pack member in the inspected manifest, while
Debugpy declares a dependency on Python. The current explicit Python/debugpy
and Jupyter/renderers choices preserve those distinctions.
[Manifest contract](https://code.visualstudio.com/api/references/extension-manifest).

Adding a program to `buildInputs` alone does not put it on the editor's runtime
PATH. Likewise, adding a library does not automatically repair a prebuilt
binary. Use supported executable settings where available; they also retain
Nix store references. For native binaries, inspect the recipe's patching hooks
and required libraries. A wrapper changes only processes launched through it.
[Nixpkgs dependency and wrapper documentation](https://nixos.org/manual/nixpkgs/unstable/#ssec-stdenv-dependencies).

For example, the existing Python module pairs the catalog client with an
explicit editor-owned formatter:

```nix
programs.vscode.profiles.default = {
  extensions = config.lib.vscode.catalogExtensions [ "charliermarsh.ruff" ];
  userSettings."ruff.path" = [ (lib.getExe pkgs.ruff) ];
};
```

The project still supplies its Python environment and imports. Add Ruff to
`home.packages` only if a general CLI installation is also wanted. Python
notebook execution needs a kernel in the selected environment; the extension
alone does not supply one.
[Kernel management](https://code.visualstudio.com/docs/datascience/jupyter-kernel-management).

Put reusable source rewrites, bundled-library repairs, and runtime wrappers in
`pkgs/`, following its own contributor policy. Keep extension selections and
supported path settings in `modules/home/vscode/`. Root `flake.nix` and
`flake.lock` own the catalog inputs. Development modules may provide CLI
conveniences, but editor modules should not import them merely to obtain a
language server. For remote work, provision the same requirements on the remote
host or override paths there; local store paths are not remote provisioning.

One pinned nix4vscode implementation detail matters for custom decorators: its
public functions close over a separately imported package set. Matching the
nixpkgs input revision does not automatically include every caller overlay.
Close over the required caller packages explicitly rather than assuming a
callback's `pkgs` includes those overrides.
[Pinned flake](https://github.com/nix-community/nix4vscode/blob/c06b9236b78dde9a0db7ae1ceeae587b374221c6/flake.nix).

## Validation and limits

The implementation gives catalog selection one owner in
`modules/home/vscode/catalog.nix`, including theme extensions. It uses the
configured editor package's version. An external or unversioned editor can set
`programs.vscode.extensionCompatibilityVersion`; otherwise it falls back to the
pinned Nixpkgs editor version. Curated Jupyter remains an explicit source choice
in the notebook module; Python keeps its newer catalog client and explicit
server paths.

The maintained dependency checker validates required extension dependencies
against the selected extensions and editor built-ins. Its unit cases cover
transitive dependencies, case-insensitive identifiers, optional packs, duplicate
identifiers, and malformed manifests. The composition check covers independent
language selectors, Linux/Darwin integration, version selection, and rejection
of an editor below curated Jupyter's supported floor.

On 2026-11-09, the complete bounded build passed with six GiB and the host's
eight compiler workers. Composition, shell integration, seven dependency-checker
unit cases, and the actual 42-extension dependency closure passed. The successful
artifact was imported and the four scoped Home Manager paths were activated
with rollback references. The active CLI reported all 42 exact declared versions.
The editor stayed at 1.142.0 and the system generation stayed unchanged.

An isolated native extension-host probe passed project EditorConfig indentation,
Bash formatting with a four-space project override, Markdown hard-break
preservation, Java's registered implementation-lens setting, and curated
Jupyter's serializer and writable temporary storage. These checks do not execute
a notebook kernel or establish authenticated chat, remote-host, or Darwin runtime
compatibility. Background notebook preload reported that the fallback Python
environment lacks Jupyter/notebook packages; select a project kernel for execution.

Earlier admission failures, the four-GiB reclaim failure, a private-cache
ownership failure, and two native test-harness failures remain recorded privately.
They were corrected or superseded by the complete passing attempts. Six GiB is
a successful observed allocation for this packet, not a universal build budget
or an editor performance benchmark.

### Bundled Copilot limitation

Native logs exposed a separate issue in the unchanged editor package. VS Code
1.142.0 bundles Copilot Chat 0.70.0, whose manifest requests `authIssuers`, while
the product allowlist omits that proposal. The separately selected Nixpkgs 0.48.1
client is redundant for this editor: the editor's built-in-update policy skips
user replacements without its required update metadata. Consequently the CLI's
declared extension version does not prove which client runs.
[Exact editor scanner](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/platform/extensionManagement/common/extensionsScannerService.ts#L385-L394).

Development mode allows the extra proposal during extension tests, so those
passes cannot certify ordinary Copilot authentication. The product allowlist
overrides extension declarations before command-line API grants are applied;
blanket API flags do not resolve this packaging mismatch.
[Proposal handling](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/workbench/services/extensions/common/extensionsProposedApi.ts#L70-L99),
[authentication API gate](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/workbench/api/common/extHost.api.impl.ts#L324-L357).

A follow-up editor-package repair should reconcile the bundled manifest and
allowlist, then verify normal-mode authentication and explicit ownership of
bundled versus separately packaged Copilot. That requires editor-package and
launcher activation beyond the four-path settings/extensions deployment performed
here. The current work preserves the existing editor and records this remaining
defect rather than claiming authenticated Copilot passed.
