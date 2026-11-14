# Modular VS Code configuration

Reviewed: 2026-11-09. Scope: Home Manager editor modules, installed VS Code
1.142.0 and extension manifests, with primary-source language research.

## Answer

The editor should supply its own language-service executables without requiring
the `dev` selectors. Projects should supply their compilers, interpreters,
dependencies, build flags, and formatter/linter policy. Keep one semantic
provider and one default formatter per language; specialized linting is a
separate responsibility. This is a design recommendation, not a measured
performance result.

## Module structure and selection

[`default.nix`](../../modules/home/vscode/default.nix) owns installation,
immutable extensions, updates and platform launch integration. `settings.nix`
owns editor preferences and optional Git/direnv integration. Its `base/` modules
own terminal behavior, security, watcher policy and structured-file support.
`base/javascript-tools.nix` is imported once by cooperating web language modules.
Language modules import the base themselves; none imports a development module.
`extensionRegistry` names the catalog, while `extensions` remains the upstream
Home Manager option. Existing public selector paths remain stable.

Select `vscode` for the base, or individual selectors such as
`vscode-languages-python`, `vscode-languages-rust`, `vscode-languages-go`, and
`vscode-languages-lua`. `vscode-languages-notebooks` adds Python and Jupyter.
`vscode-languages` intentionally selects the entire language collection; it is
convenient but installs more extensions and tooling than an explicit selection.
`vscode-ai` remains separately selected. Theme ownership remains with Stylix.
No new editor module changes a container daemon, installs project dependencies,
or enables a development feature.

## Findings and sources

| Language/configuration | Editor owner and integration decision |
| --- | --- |
| Nix | Nix IDE, explicit nixd/nixfmt. nixd executes formatter arguments verbatim, so remove the literal `--filename={file}` argument. Keep host option evaluation project-specific. [Nix IDE](https://github.com/nix-community/vscode-nix-ide), [nixd configuration](https://github.com/nix-community/nixd/blob/main/nixd/docs/configuration.md), [formatter execution](https://github.com/nix-community/nixd/blob/main/nixd/lib/Controller/Format.cpp). |
| Bash | Bash IDE already integrates ShellCheck and shfmt; remove duplicate standalone clients, pin executables, retain project EditorConfig support. [Bash language server](https://github.com/bash-lsp/bash-language-server/tree/main/vscode-client). |
| Nushell | Its extension launches `nu --lsp`; pin `nushellLanguageServer.nushellExecutablePath` independently of the user's login shell. [Extension schema](https://github.com/nushell/vscode-nushell-lang/blob/main/package.json). |
| Rust | Explicit rust-analyzer; project Cargo/toolchain supplies Clippy and rustfmt. Keep warning denial optional and preserve the shared manual-save formatting policy. Build scripts and proc macros execute project code. [Configuration](https://rust-analyzer.github.io/book/configuration.html). |
| C/C++ | clangd owns diagnostics/completion/formatting; pin its binary, avoid self-downloads and automatic CMake configuration. Generate `compile_commands.json` in the project. A broad `--query-driver` permits compiler execution, so never enable one globally. [Setup](https://clangd.llvm.org/installation), [compile commands](https://clangd.llvm.org/design/compile-commands). |
| JavaScript/TypeScript | Built-in language services already provide imports, paths and npm integration. Remove redundant helper extensions. ESLint owns configured project rules; Prettier requires project configuration and does not resolve global modules. [JavaScript](https://code.visualstudio.com/docs/languages/javascript), [TypeScript](https://code.visualstudio.com/docs/languages/typescript), [Prettier](https://github.com/prettier/prettier-vscode#configuration), [ESLint](https://github.com/microsoft/vscode-eslint#settings-options). |
| Oxc | `requireConfig` gates Oxlint only. Disable the separate Oxfmt client while Prettier owns formatting; expose explicit Nix paths for project opt-in. Both lint engines run on save. A project enabling both linters may receive overlapping diagnostics and should choose its policy. [Oxc client](https://github.com/oxc-project/oxc-vscode/tree/main/client/tools). |
| HTML/CSS/SCSS/Less | Built-in formatters work without project dependencies; Tailwind IntelliSense uses the workspace's Tailwind configuration. Projects using Prettier can select it locally. [HTML](https://code.visualstudio.com/docs/languages/html), [CSS](https://code.visualstudio.com/docs/languages/css), [Tailwind](https://github.com/tailwindlabs/tailwindcss-intellisense). |
| Python | Python/debugpy, ty for semantic analysis, Ruff for formatting/linting; remove disabled Pylance and global lint suppressions. Pin ty and Ruff, preserve project interpreter selection. Activate environments normally unless direnv owns activation. [ty](https://docs.astral.sh/ty/features/language-server/), [Ruff](https://github.com/astral-sh/ruff-vscode). |
| Notebooks | Separate Jupyter/renderer selector; project kernels supply `ipykernel`. Colab is an optional external compute service, not required Python support. [Kernel management](https://code.visualstudio.com/docs/datascience/jupyter-kernel-management). |
| Java | Red Hat language support, debugger, tests and build navigation. Tooling JVM and project runtime are distinct; remove global legacy runtime mappings. Ask before refreshing changed build configuration. The locked Nixpkgs `temurin-bin` alias still selects JDK 21, so use `temurin-bin-25` for the tooling JVM required by current Java extension releases. [Java requirements](https://github.com/redhat-developer/vscode-java#requirements). |
| Go | Go extension with explicit gopls/Delve and tool self-updates disabled. Leave Go version, GOROOT and GOPATH project-owned. [Extension settings](https://github.com/golang/vscode-go/blob/master/docs/settings.md). |
| Lua | LuaLS with explicit executable and its own formatter. `.luarc.json` owns runtime version, globals and library paths. [LuaLS settings](https://luals.github.io/wiki/settings/), [formatter](https://luals.github.io/wiki/formatter/). |
| Typst | Tinymist supplies formatting and language service. Lint on save and leave PDF export explicit by default; projects may enable export on save. [Tinymist settings](https://myriad-dreamin.github.io/tinymist/config/vscode.html). |
| MATLAB | Official extension owns formatting when supported MATLAB is installed; connect on demand, disable its telemetry, retain user-owned installation/licensing. [MathWorks extension](https://github.com/mathworks/MATLAB-extension-for-vscode). |
| Solidity | Nomic's extension owns semantics and formatting; choose Forge only in projects supplying Foundry. Disable extension telemetry. [Nomic extension](https://github.com/NomicFoundation/hardhat-vscode). |
| JSON/JSONC | Built-in language features and formatting; schemas remain project-specific. [JSON support](https://code.visualstudio.com/docs/languages/json). |
| YAML/Actions | Red Hat YAML formatter and GitHub Actions intelligence. Keep specialized GitHub workflow exclusions; remove Gitea/Forgejo exclusions without another validation owner. Repository CI's yamlfmt/actionlint/yamllint pipeline can differ from editor formatting. [YAML](https://github.com/redhat-developer/vscode-yaml), [Actions](https://github.com/github/vscode-github-actions). |
| TOML | Even Better TOML with bundled Taplo disabled and explicit Nix executable. Project Taplo configuration owns formatting policy. [Taplo extension](https://github.com/tamasfe/taplo/tree/master/editors/vscode). |
| Markdown | Built-in preview/link validation, wrapping, and preserved hard-break spaces. Repository rumdl checks remain authoritative; no second Markdown lint engine is installed globally. [Markdown support](https://code.visualstudio.com/docs/languages/markdown). |
| just/CSV | just's extension already starts just-lsp; pin just and just-lsp without a second client. Keep Rainbow CSV; remove the additional CSV editor. [just extension](https://github.com/nefrob/vscode-just), [Rainbow CSV](https://github.com/mechatroner/vscode_rainbow_csv). |
| Containers | Retain optional Container Tools and Dev Containers. The runtime/socket/context belongs to the host and project. Do not add overlapping Docker DX services automatically. [Container Tools](https://github.com/microsoft/vscode-containers), [Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers). |

## Security, resources and development integration

[Workspace Trust](https://code.visualstudio.com/docs/editing/workspaces/workspace-trust)
remains enabled with a startup prompt and a separate window for untrusted files.
It does not sandbox extensions. Declarative, immutable extensions and locked
updates reduce uncontrolled changes; they still require timely flake updates
and review. Remove unnecessary collaboration, file-operation and duplicate
language extensions to reduce executable extension surface. Use the editor's
built-in source-control graph rather than installing another graph provider.
[Extension security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security)
describes extensions' access to files, processes and networks.

Watcher exclusions cover dependency/generated trees without hiding files from the
Explorer. A project whose source lives under `target` must override that
exclusion. These settings do not constrain every extension's own watcher or
indexer. No fixed language-server heap/thread limits are imposed without
measurements. Use extension profiling and representative projects before claiming
CPU or memory improvements. [File watcher interface](https://code.visualstudio.com/api/references/vscode-api#workspace.createFileSystemWatcher).

Optional `dev-direnv` supplies approved project environments; the editor adds its
integration only when enabled. The explicit project trust decision and
`direnv allow` remain separate approvals. Existing development language modules
supply useful global CLI fallbacks, but an editor language server's absolute Nix
path does not pin the project's compiler or dependencies. The Rust development
module currently exports a global `RUST_SRC_PATH`; projects using a different
toolchain should unset or override it to avoid mismatched standard-library
sources. Remote SSH and Dev Containers execute workspace tools remotely, so local
Nix store paths require corresponding remote tooling/settings; this configuration
does not provision those hosts automatically.

Manual Save formats supported documents then saves; focus-change autosave keeps
its existing unformatted behavior. The keybinding now checks `files.autoSave`,
the actual setting. Rust follows that same policy. On Darwin, `VISUAL=code`
uses the managed copied application launcher rather than the Nix-store bundle.
Markdown preserves trailing spaces. Git signing is enabled only when the configured signing preference is
true, and sync/parent-repository discovery require explicit confirmation.

## Extension and settings follow-up

The 2026-11-09 audit compared all 40 selected Marketplace extensions with the
official stable-release metadata and refreshed only the nix4vscode lock node.
The proposed update advances Ruff, ty, Tinymist, Material Icon Theme, and
rust-analyzer. The catalog carries rust-analyzer 0.3.3105 while the Marketplace
already reports 0.3.3113; a daily catalog pin can lag a newly published release.
This is a reproducible update, rather than a claim that every extension always
matches the newest Marketplace upload.

The base now includes official EditorConfig support so project indentation
reaches formatter options. Bash falls back to spaces, and this repository's
Markdown section explicitly preserves hard-break spaces when EditorConfig saves
files. The integration uses the maintained
[EditorConfig extension](https://github.com/editorconfig/editorconfig-vscode/releases/tag/v0.18.2).

Java implementation lenses now use `java.implementationCodeLens = "types"`,
which the [installed-version schema](https://github.com/redhat-developer/vscode-java/blob/v1.58.0/package.json)
registers. Error Lens uses a positive 500 ms debounce delay; its previous
save-timeout setting was inactive with live-diagnostic defaults. The orphan
GitHub issue-completion setting was removed.
[Error Lens settings](https://github.com/usernamehw/vscode-error-lens#settings-76).

The audit retains ty for Python language services alongside Ruff; Astral's
[editor guidance](https://docs.astral.sh/ty/editors/) disables the Python
extension's competing language server. Project interpreters and notebook
kernels remain project-owned. The
[extension source policy](vscode-extension-sources-research.md) explains curated
Jupyter, stable catalog selection against the actual editor, and dependency
ownership.

## Startup migration and formatter identifiers

The startup rewrite reported after activation was `extensions.autoUpdate`:
the generated value was `false`, while VS Code 1.142 migrates that retired
boolean to `"off"`. On an immutable settings file, the edit cannot be saved,
so the migration repeats at startup. The base module now emits `"off"` directly
for compatibility versions 1.142 and newer, overriding Home Manager's boolean.
Earlier compatibility versions retain their previous representation.
[Exact editor schema and migration](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/workbench/contrib/extensions/browser/extensions.contribution.ts#L2058-L2083).

MATLAB's formatter identifier is `MathWorks.language-matlab`. Although extension
lookup accepts lowercase identifiers, the default-formatter JSON schema lists
the registered identifier with its original casing. The language module now
uses that spelling; the registry lookup keeps its lowercase catalog key.
[Formatter schema construction](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/workbench/contrib/format/browser/formatActionsMultiple.ts#L107-L119),
[MathWorks manifest](https://github.com/mathworks/MATLAB-extension-for-vscode/blob/v1.3.15/package.json).
This repairs the settings diagnostic; MATLAB formatting still requires a
compatible MATLAB installation and connection.

The original configuration reproduced both failures in an isolated editor:
after delayed startup migration, the settings document was changed and the
MATLAB identifier did not match the registered schema spelling. The fixed
configuration passed two independent launches with a 20-second passive startup
observation in each; the settings file and open document stayed unchanged and
clean. Linux/Darwin composition and the legacy editor compatibility case passed.
The two corrected settings were activated on the desktop with rollback references.
An existing dirty settings tab can retain the earlier migration edit until it
is reverted and the window is reloaded. Native MATLAB execution was not tested.

## Validation and limits

Research inspected installed manifests and first-party documentation. Installed
versions included Nix IDE 0.5.13, Bash IDE 1.43.2, Nushell 2.0.6, rust-analyzer
0.3.3089, clangd 0.6.0, ESLint 3.0.34, Prettier 12.4.0, Oxc 1.64.1, just 0.10.2,
YAML 2.0.0 and Even Better TOML 0.21.2. Upstream main can differ from locked
extension versions; avoid adding settings solely because main supports them.

The focused [composition check](../../tests/nix/vscode-configuration.nix)
exercises Linux and Darwin modules without importing development features,
standalone selection, merged settings, actual extension derivation resolution,
optional direnv behavior, and signing preference. The existing shell integration
check covers executable selection and the Copilot Bash hook. These checks do
not launch VS Code or prove formatter, debugger, remote-host or licensed runtime
behavior. Native Darwin and representative language-project smoke tests remain
necessary before claiming full project runtime compatibility.

On 2026-11-09, the composition and shell-integration checks both built
successfully using the documented bounded private-store builder. Final validation
followed repairs to nullable keybinding conditions in the test fixture and the
optional direnv extension's catalog resolution. Static formatting, deadnix,
statix, Markdown lint, and local documentation links passed.

Scoped desktop activation installed the four generated VS Code paths (settings,
keybindings, MCP configuration, and immutable extensions) with rollback references.
The editor package remained VS Code 1.142.0; the extension set changed from 61 to
41. The active CLI reported exactly the declared 41 extensions, and all 18
configured executable version probes passed, including Java 25. These probes
establish that the selected binaries execute, rather than proving project
completion, formatting, debugging, or remote integration. No native Darwin
activation or performance benchmark was performed. The full system generation
and unrelated configuration were left in place.

For package-provider selection, channel/platform variants, and runtime dependency
ownership, see [extension source policy](vscode-extension-sources-research.md).

The follow-up source-policy and settings build also passed on 2026-11-09,
including seven dependency-checker unit cases and the actual extension closure.
Scoped activation now installs 42 managed extensions, including EditorConfig and
the five refreshed catalog clients. An isolated native extension-host probe
verified project indentation reaching Bash formatting, Markdown hard-break
preservation, the Java implementation-lens setting, and curated Jupyter notebook
loading with writable temporary storage. The active CLI reported the exact
42 declared versions. The editor and system generation remained unchanged.

The native logs also exposed the unchanged editor's bundled Copilot API mismatch;
see the [source-policy limitation](vscode-extension-sources-research.md#bundled-copilot-limitation).
Development-mode tests do not establish ordinary Copilot authentication. Notebook
kernel execution, remote workflows, native Darwin activation, and performance
benchmarks remain unverified.
