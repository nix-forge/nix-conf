# Nix function conventions

Choose script and substitution helpers by the job they perform. Using one
function everywhere would weaken validation in some places and change runtime
behavior in others.

## Templates and text replacement

Use `pkgs.replaceVars` for a source file whose `@name@` placeholders need no
extra derivation settings. Use `pkgs.replaceVarsWith` when the rendered file
also needs a name, destination, executable bit, metadata, or a `postCheck`.
Both helpers fail for declared placeholders that are absent and for undeclared
placeholder-shaped text left in the result. Escape each replacement for its
destination format. The template helper does not know whether a value is Bash,
JSON, XML, CSS, or another language.

Use `builtins.replaceStrings` for small strings assembled during Nix
evaluation. It is appropriate for transformations such as version-name
normalization and for module options that require text rather than a store
path. Add explicit assertions when replacement completeness affects
correctness.

Use `substituteInPlace` only in package build phases that edit unpacked source.
Expected upstream text must use `--replace-fail`, so an upstream change fails
the build. Use `pkgs.substitute` when the input must remain unchanged and the
result should be a separate derivation with arbitrary literal replacements.

The [Nixpkgs build-support manual](https://nixos.org/manual/nixpkgs/stable/#sec-build-support)
documents these helpers and the
[`substitute` flags](https://nixos.org/manual/nixpkgs/stable/#fun-substitute).

## Bash programs

Use `pkgs.writeShellApplication` for a short installed Bash command. Put its
command dependencies in `runtimeInputs`. The helper adds a Bash shebang,
strict options, syntax validation, ShellCheck, and a runtime `PATH`. Do not add
a second shebang. Set `inheritPath = false` only when every command dependency
is declared and the program is not meant to call a user-selected or host-native
command.

Use `myLib.writers.writeBashTemplate` for a repository Bash source file that
contains `@name@` placeholders or benefits from living outside the Nix module.
The writer performs strict replacement, removes a known Bash shebang, validates
the rendered program, and supports `runtimeInputs`. A source file without a
shebang must set its own shell options. This keeps its behavior visible when a
maintainer reads the source by itself.

Reserve `writeShellScript` for a store-path script used as a module or test
implementation when direct executable paths or an intentional ambient `PATH`
make a runtime wrapper unnecessary. Reserve `writeShellScriptBin` for the same
small case when callers need a package-shaped `bin` directory, especially test
doubles. New installed commands should normally use `writeShellApplication`.

The [Nixpkgs trivial-builder manual](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-writeShellApplication)
describes the shell writers and their checks.

## Python programs

Use `pkgs.writers.writePython3Bin` for one small executable Python file and
`pkgs.writers.writePython3` when a caller needs a single executable store path.
Declare imported Python packages in `libraries`. Keep Ruff, type checks, and
behavior tests as the repository's main checks. The writer's Flake8 run is an
additional build-time check, so limit `flakeIgnore` to conflicts with the
project formatter.

Use `buildPythonApplication` for a distributable Python application with a
source tree, build backend or wheel, declared dependencies, entry points, and
package tests. Script length alone is not a reason to switch builders. The
[Nixpkgs Python manual](https://nixos.org/manual/nixpkgs/stable/#buildpythonapplication-function)
documents the application builder.

Use `python3Packages.buildPythonPackage` for an imported library, with its native
source tree, build backend, import checks and package tests. Consumers declare
the built library in a Python writer's `libraries` or `python3.withPackages`.
Keep a library reused across repositories in the package repository, so each
consumer can declare the same dependency. Standalone package updaters have a
separate independence contract: they may carry a native helper copy when personal
package dependencies are forbidden. The package layout and contract checks require
those copies to match the canonical implementation byte for byte.

## Configuration ownership

Keep deployment choices in the owning Nix module: selected packages, paths,
initial application preferences, feature dependencies, and resource policy.
Pass resolved values to native programs through quoted arguments or generated
configuration files. Use `pkgs.formats` generators for supported structured
formats, and keep credentials in runtime files outside the store.

Expose typed options for supported variations. Use conditional definitions for
optional integrations and assertions for required dependencies. Derive coupled
values, such as a recording deadline and sample count, from one setting. Read
Home Manager's configured paths rather than reconstructing `~/.config`, and use
the selected program package instead of an unrelated default package.

Preserve undeclared settings during reconciliation. Creation defaults apply to
new objects; they must not overwrite existing UI choices unless the user
explicitly manages that field. Keep protocol constants, parser bounds, and
algorithm details in the native program rather than adding options without a
supported use case. The [NixOS module manual](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
documents typed options, conditional definitions, and assertions; the
[Nixpkgs manual](https://nixos.org/manual/nixpkgs/stable/#sec-format-generators)
documents configuration generators.

## Executable references

Use `lib.getExe package` when the package declares `meta.mainProgram`, and
`lib.getExe' package "command"` for another named executable. Use an explicit
store-relative path only when the executable is outside `bin` or package
metadata cannot identify it. This makes callers follow package metadata instead
of duplicating output layout.

## Source files and language tooling

Keep maintained programs in files with their language's extension. Nix owns
package selection, dependencies, option values, and references to those files.
This applies to installed commands, activation hooks, package phases, VM test
drivers, and compiler fixtures. Keep deliberately invalid source inside the test
that checks its rejection. Small command arguments such as a fixed `jq` filter
can remain beside their caller.

| Source                                                             | Nix integration                                                                                            | Source checks                                            |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Bash `.sh` or `.sh.in`                                             | `writeShellApplication`, `writeBashTemplate`, or a package phase                                           | shfmt, ShellCheck, rendered Bash syntax                  |
| Python `.py`                                                       | `writePython3`, `writePython3Bin`, `buildPythonApplication`, or a declared build interpreter               | Ruff, ty, compilation, behavior tests                    |
| JavaScript `.js`, `.cjs`, `.mjs`; TypeScript `.ts`, `.cts`, `.mts` | `writeJS` for a small command; the package's Node builder and declared runtime for applications and checks | Prettier, Oxlint, TypeScript where applicable            |
| Nushell `.nu` or `.nu.in`                                          | `writeNu` for commands; the existing Nu configuration checker for generated configuration                  | nufmt on valid source; `nu-check` on rendered templates  |
| Lua `.lua`                                                         | `writeLua` for commands or a source reference for application configuration                                | StyLua and the consuming Lua runtime                     |
| Rust `.rs`, Go `.go`                                               | `writeRust` for a small standalone program; `buildRustPackage` or `buildGoModule` for applications         | rustfmt or gofmt, compiler and package tests             |
| C `.c`, C++ `.cc`, Swift `.swift`                                  | compiler inputs declared in the package recipe                                                             | clang-format or swift-format, native compilation         |
| PowerShell `.ps1`                                                  | `writePowerShell` with the declared PowerShell runtime                                                     | PowerShell parser, PSScriptAnalyzer, rendered checks     |
| PHP `.php`                                                         | a declared PHP interpreter and native source reference                                                     | PHP syntax and runtime behavior checks                   |
| JQ `.jq`                                                           | `writeText` for a rendered filter, or a source reference passed to the declared `jq` interpreter           | native parser and assertion checks                       |
| AWK `.awk`                                                         | a source reference passed to the declared GNU awk interpreter                                              | GNU awk pretty printer and native parser/behavior checks |
| Tcl or Expect `.tcl`, `.exp`                                       | the declared Tcl or Expect interpreter and a source reference                                              | tclfmt, tclint, protocol behavior checks                 |
| Dart `.dart`                                                       | a source reference passed to the declared Dart SDK for a fixture or application build                      | Dart formatter and native execution of rendered fixtures |
| macOS Seatbelt `.sb`                                               | a source reference for the check's `sandboxProfile`                                                        | the native sandbox parser during the check build         |
| PostgreSQL `.sql`, CMake `.cmake`                                  | a source reference passed to the database client or build system                                           | SQL formatter or cmake-format, native integration checks |

The pinned [Nixpkgs writer implementation](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/build-support/writers/scripts.nix)
is the authority for supported writers and their arguments. Do not wrap a build
check as an installed application just to use a writer. A declared interpreter
executing a checked source file is sufficient for a package phase.

When a module option or package phase needs a Nix string, use the owning
repository's pure text renderer. The root implementation is
[`lib/templates/text.nix`](../lib/templates/text.nix). It validates replacement
names and completeness, preserves store context, and permits `null` only to
retain an explicit literal marker. Escape replacements for the destination
language before calling it. Replacement values are literal and are not rendered
again. Use `pkgs.replaceVars` for files that must be produced during a build.
Never read a replacement derivation back into evaluation with `builtins.readFile`.
That introduces import-from-derivation and can turn evaluation into a build.

Moving stdin or `node -e` programs into files changes import lookup. Preserve an
application's working-directory imports explicitly with `PYTHONPATH`, Python's
`sys.path`, or Node's `createRequire`. Keep smoke-test imports observable through
`importlib.import_module` so a linter cannot remove them as unused variables.

Standalone packages and exported flake templates carry their renderer and helper
sources inside their own directories. The package independence check compares
local helper copies with the catalog versions to prevent drift.

Keep exact upstream patch fragments in language templates such as `.js.in`.
Check the assembled program with its native parser or compiler; an incomplete
fragment cannot be validated as a standalone program. Retain upstream hashes
and unique-anchor checks so a version change requires review.

HTML templates also belong in `.html.in` files. Preserve quoting and whitespace
when fragments are assembled or substitution occurs inside attributes; formatting
an incomplete fragment can insert closing tags or change its quoting. Validate
the assembled document in its owning browser check. Keep complete HTML and CSS
sources under their native formatter.

Run source-rewriting linters before their formatter. The repository Nix pipelines
use deadnix, then Statix, then nixfmt, and finally nixf-diagnose. Treefmt applies
matching tools in ascending priority, then alphabetical order. Explicit priorities
keep a later rewrite from invalidating formatting. See the
[Treefmt ordering contract](https://treefmt.com/v2.1/getting-started/configure/#same-file-multiple-formatters).

Spelling checks are read-only. Review corrections before applying them, and record
valid protocol identifiers in the spelling configuration. Each repository owns
its source checks; root hooks and formatters exclude submodule sources.

Python fixture templates retain `.py.in` names. Their dedicated Ruff formatter
maps the template extension to Python; their owning tests execute the rendered
programs. SQLite fixture formatting uses the SQLite dialect separately from
PostgreSQL service schemas. See [Ruff extension mappings](https://docs.astral.sh/ruff/settings/#extension)
and the [SQL Formatter dialect options](https://github.com/sql-formatter-org/sql-formatter#usage).
