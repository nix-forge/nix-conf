# Additional command-line tools for coding agents

Reviewed: 2026-11-15. Scope: reusable Home Manager development and CLI modules
for Linux and Apple Silicon macOS.

## Answer

Add four focused tools: Mike Farah's yq, Difftastic, Hyperfine and Watchexec.
They provide structured configuration queries, structural code review,
repeatable command timing and event-driven command execution. Keep them as
explicit commands rather than changing Git defaults or starting services.

## Findings and sources

The existing modules already select Git hosting clients, ripgrep, jq, ast-grep,
language compilers and linters, Playwright, PDF tools and media utilities.
These additions address different tasks:

| Command | Selected package | Use |
| --- | --- | --- |
| `yq` | `yq-go` 4.54.1 | Query and transform YAML and other structured configuration |
| `difft` | `difftastic` 0.72.0 | Inspect changes using syntax trees |
| `hyperfine` | `hyperfine` 2.0.0 | Measure repeatable command execution and export results |
| `watchexec` | `watchexec` 2.5.1 | Run a task when watched files change |

These are observed versions in the evaluated package set, not claims about the
latest upstream releases.

[Mike Farah's yq](https://github.com/mikefarah/yq) supplies a standalone
structured-data processor with jq-style expressions. Select `pkgs.yq-go`
explicitly: other packages also use the name yq. This provides configuration
queries without requiring an ad hoc Python environment.

[Difftastic](https://difftastic.wilfred.me.uk/introduction) compares parsed code
and falls back to line-based diffing when necessary. Its manual currently
describes a newer release than the selected package. The repository keeps its
existing Delta integration; `difft old.nix new.nix` is available separately.
Use ordinary Git patches when a consumer needs patch-compatible output.

[Hyperfine](https://github.com/sharkdp/hyperfine) supplies command benchmarking,
repeated execution and export formats. The selected 2.0.0 emits JSON schema
version 2: samples are under `results[].measurements`, rather than the older
`times` array. Inspect the installed version's output before writing consumers.
The smoke check verifies execution and export, not a performance improvement.

[Watchexec](https://github.com/watchexec/watchexec) responds to file changes and
runs commands. It is useful for task-local lint or build loops across languages.
The module installs the CLI only. The caller owns watcher lifetime and cleanup;
no persistent service or repository watch policy is installed.

## Validation and limits

The four modules evaluate with available packages for `x86_64-linux` and
`aarch64-darwin`. The Linux package outputs were realized successfully using the
selected Nixpkgs source. Smoke checks verified:

- A YAML field query with JSON output.
- A structural JavaScript diff and its changed-file exit status.
- Hyperfine JSON export with successful measurements in schema version 2.
- Watchexec's initial execution, a second execution after a file change, and
  termination of the task-owned watcher.

The first Hyperfine smoke-check parser expected the old JSON format and failed;
the emitted schema was inspected and the corrected check passed. Nix formatting,
deadnix and statix checks passed for the module changes. These checks do not
establish native macOS behavior or full host-profile activation. No deployment
was performed and no project-owned behavioral test suite was added.

## Implication for this repository

The development aggregate selects
[Difftastic](../../modules/home/dev/difftastic.nix),
[Hyperfine](../../modules/home/dev/hyperfine.nix) and
[Watchexec](../../modules/home/dev/watchexec.nix) for both workstation profiles.
[yq](../../modules/home/cli/yq.nix) is selected by the Mac profile's CLI aggregate
and explicitly by the desktop profile. Existing skill/plugin selection, Git
integration and project-specific dependency environments retain their owners.
