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

## Executable references

Use `lib.getExe package` when the package declares `meta.mainProgram`, and
`lib.getExe' package "command"` for another named executable. Use an explicit
store-relative path only when the executable is outside `bin` or package
metadata cannot identify it. This makes callers follow package metadata instead
of duplicating output layout.
