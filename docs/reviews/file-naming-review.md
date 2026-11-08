# File naming review

Reviewed on 2026-10-11.

Reviewed the tracked and nonignored file inventory in the root repository and
all four submodules. The baseline contained 3,703 files. This pass renamed 820
sources and assets after tracing their callers.

| Repository | Files reviewed | Files renamed |
| --- | ---: | ---: |
| Workstation configuration | 1,786 | 261 |
| Package recipes | 1,115 | 390 |
| Homelab modules | 433 | 123 |
| Secret management | 262 | 46 |
| Configuration framework | 107 | 0 |

## Naming decisions

Python sources now use snake_case, including standalone executables, VM drivers
and generated fixture templates. This follows
[PEP 8 module naming](https://peps.python.org/pep-0008/#package-and-module-names).
Installed commands keep their established command names.

Shell helpers and ordinary assets use lowercase kebab-case. Names describe
behavior or package lifecycle phases. Extraction ordinals, source line numbers,
interpolation punctuation and ambiguous `name-*` or `default-hook` labels have
been removed. Separate fixtures retain separate files named for the scenario
that consumes them, even when their contents happen to be identical.

Examples include `prepare-direnv-directories.sh`, `check_emoji_artwork.py`,
`nonfinite_timeout_command.py`, `install-darwin-extension-policy.sh`,
`network.xml`, and `storage-pool.xml`. Package phase helpers use names such as
`post-install.sh` and `install-check-phase.sh`.

The [layout guide](../layout.md) records the conventions for future additions.

## Names retained deliberately

Native manifests, lockfiles, entry points and community-health files retain
their required names. Rust and C++ source names follow their language conventions;
React component names and Swift source names retain native capitalization.
Real version numbers, schema versions, decision numbers and architecture names
remain meaningful identifiers.

Public module selectors, package identities, runtime units, command names and
secret names remain stable. Framework fixture names deliberately exercise
filename discovery and aggregation, so none needed renaming. JavaScript helpers
being converted to TypeScript by concurrent work were preserved for that task.

## Migration checks

Callers, source filters, Python imports, fixture loaders, package-local helper
inventories, documentation links and per-file lint selections were updated.
Template replacement keys remain paired with their existing placeholders.
File permissions and pre-existing staged index entries were verified against
the baseline.

Source parsing and formatting passed for the affected Python, Bash and Nix
sources. Focused behavior checks passed 394 tests and 23 subtests. Independent
review found a derived Bluetooth policy filename; its loader was corrected and
the focused regression suite passed. No review findings remain unresolved.

Full Nix evaluation and broader checks remain queued through the desktop
workload runner.
Passing source checks does not establish a successful system build or activation.
