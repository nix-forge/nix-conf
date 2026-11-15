# Checker and ignore-rule audit

The September 2026 audit covers the root configuration and the `pkgs`,
`nix-seal`, and `nix-config-framework` submodules. The checkout also contains
concurrent desktop and font work; this record describes checker changes only.

## Corrections

- Restore Gitleaks' default detection rules in every custom configuration.
  The former allowlist-only configurations missed a synthetic GitHub token.
  Exceptions now require a matching detector, path, and value. Public cache
  hashes and download URLs no longer exempt entire files. The
  `gitleaks-policy` Nix check verifies provider and generic credentials remain
  detectable inside paths with exceptions.
- Use exact Git-history fingerprints for three historical nix-seal fixtures
  and seven historical root false positives.
  New credentials in those paths remain subject to detection.
- Load `.typos.toml` explicitly in hooks. The generated hook configuration had
  overridden the repository configuration. Remove stale words and broad font
  manifest exclusions; retain exact upstream identifiers, including Apple's
  `Produkt` and the OpenType `wdth` axis tag, and generated hashes.
- Respect each submodule's Ruff configuration. Supply Python dependencies to
  type checking, fix incorrect types and callback interfaces, validate IPC
  responses, and redirect compilation caches outside source trees.
- Enable previously disabled Markdown rules except prose line length. Remove
  obsolete Git ignores and redundant shebang, EditorConfig, and SwiftLint
  exceptions. Preserve significant patch context and captured terminal output.
- Scan GitHub workflows at every severity. Document required permissions,
  remove unnecessary dependency-review write permissions, limit overlapping
  runs, and pass matrix values through environment variables. Keep existing
  job names so required checks retain their identities. Use the runner's
  Rustup directly, with explicit directory overrides for MSRV and nightly jobs.
- Align YAML formatting and linting. Fold long expressions, allow the formatter's
  comment spacing, and recognize GitHub's YAML 1.2 `on` key. Excessive line length
  is now an error.
- Fix stale desktop assertions to account for local compositor patches and the
  portal rebuilt against that compositor. Fix the portal's unused counter,
  ignored cast qualifier, and GCC-incompatible warning flag without disabling
  diagnostics. Validate custom flake exports with
  schemas and remove locally used deprecated Nix interfaces.
- Run one treefmt wrapper per hook invocation and one root CI check target per
  Nix process, avoiding duplicated formatter startup and accumulated evaluator
  memory. Align the package submodule's treefmt-nix input with the revision
  already used by the other repositories to remove its deprecated platform
  lookup.
- Prune 13 unnecessary Cargo Vet exemptions and narrow one exemption from
  `safe-to-deploy` to `safe-to-run`. Keep six older baselines needed by imported
  audit deltas. Locked vetting succeeds with 15 fully audited, seven partially
  audited, and 239 exempted dependencies.
- Resolve Fontconfig's DTD through a local XML catalog rather than suppressing
  the diagnostic or fetching it over the network. Give emoji install checks an
  explicit Fontconfig configuration and writable temporary cache. Reject
  diagnostics even when `fc-scan` returns success.
- Correct the M PLUS variable-font filename removed when Google Fonts supplies
  the same file. The spelling formatter had expanded `wdth` to `width`. Stop
  ignoring missing removal targets and check both packages together in a
  profile to catch future collisions.

## Retained exceptions

| Area | Reason and boundary |
| --- | --- |
| Encrypted `.age` files, build outputs, caches, private local state | Binary or generated data and operational credentials do not belong in source-format checks or Git. Public policy metadata remains scanned. |
| Gitleaks public hashes, signed public download URLs, deterministic test values | Exceptions require the expected path, detector, and value. Regression canaries check that other credentials in those paths still fail. |
| Historical fixtures | Ten exact commit, path, rule, and line fingerprints cover published test data, PEM delimiters, public verification keys, and a boolean argument. No current file is exempted wholesale. |
| Ruff formatting and documentation conventions | Conflicting formatter rules are disabled. CLI output, trusted fixture XML, explicit subprocess argument lists, test assertions, and fixed random test schedules retain scoped explanations. |
| Native Python extensions | `uharfbuzz` and `lxml.etree` lack the required shipped static types. Dynamic FontTools fields and two runtime sibling imports have narrow suppressions. Installed dependencies otherwise resolve normally. |
| NixOS VM Python driver | Only its generated driver script receives the injected-name exception. Ordinary Python files are checked. |
| Upstream compositor evidence | The dated `docs/assets/hyprland-upstream-local-20260907` capture retains original bytes and checksums. Formatting and spelling tools skip it; JSON validation and secret detection still apply. Generated executables and caches remain local. |
| Large screenshot | Only `docs/assets/zen-webfonts/before.png`, a 1.1 MB rendering comparison, is exempted from the 500 KB hook limit. |
| Framework Python helpers | The framework has no Ruff project. Its own CI validates its helpers; root Ruff does not impose parent-only conventions across that repository boundary. |
| Patch whitespace, terminal captures, license text | Patch context markers and captured columns are data. License text is preserved verbatim. Other whitespace rules remain active. |
| Markdown prose line length | Long prose, links, and commands remain readable without forced wrapping. Other previously disabled Markdown checks are enabled. |
| Metadata-only `pull_request_target` workflows | Eight explicit exceptions cover reviewer and auto-merge API calls. These workflows never check out or execute pull-request code. |
| Shell template placeholders and embedded Awk, Perl, GraphQL | Nix supplies executable paths and shebangs. Embedded language variables must remain literal until their interpreter receives them. |
| Swift formatter conflicts and platform APIs | Swift formatters own layout. Finder sidebar integration requires deprecated Apple APIs; Core Foundation collection access requires its scoped cast. Native verification requires macOS. |
| Rust test helpers and long validation/transaction routines | Test-only assertions, platform-gated paths, and cohesive validation sequences retain localized exceptions. Removing them by splitting control flow merely to satisfy a size rule would obscure review. |
| Rustix network-namespace call | The pinned replacement requires unsafe code, which the workspace forbids. The existing call uses only `NEWNET`; the upstream safety concern concerns unsharing file-descriptor tables. Its local deprecation exception is documented. |
| Legacy RSA advisory | RUSTSEC-2023-0071 has no patched release. ADR 0009 limits this dependency to local legacy OpenSSH migration. The exception must be revisited on dependency changes and before any network-facing use. |
| Duplicate Rust dependencies | Exact older versions are required by incompatible upstream APIs. New duplicate versions fail; stale exceptions warn. |
| Cargo Vet exemptions | These are an explicit dependency-audit backlog, not evidence of an independent audit. Removing them or marking them audited without reviewing dependency source would misrepresent assurance. The pre-1.0 audit warning remains. |

## Validation and remaining boundaries

Pure Nix builds exercise repository hooks, Python quality, secret-detection
canaries, configuration contracts, and isolated browser/font checks. Full Git
history scans pass in all four repositories. Direct workflow checks include
Actionlint, strict Yamllint, and pedantic Zizmor with no severity threshold.
Nix-seal's Cargo check, Clippy with warnings denied, 188 package tests, all
module checks, documentation check, and activation VM passed. Cargo Deny and
locked Cargo Vet pass without warnings.

The full desktop closure, deployment schema, and activation checks passed.
The final Fontconfig configuration and cache correction was verified by running
both exact install-check phases in Nix sandboxes against the compiled font
artifacts. Each passed all 7,829 encodings without Fontconfig diagnostics. The
glyph-compilation steps were unchanged and were not repeated for that final
check-environment correction.

The desktop host runs Linux. Native Core Text, Xcode/Swift compiler analysis,
macOS sanitizers, and macOS filesystem integration require the existing Darwin
CI jobs. Interactive keyboard/focus/HDR checks require a suitable desktop test
session. Static checks do not establish their runtime result. This audit does
not claim an external security review or turn the standalone Home Manager
plaintext-storage warning into a guarantee.
Scheduled Miri, mutation-testing, and long-running fuzz campaigns were not run
locally; their existing CI jobs remain responsible for those results.
CodeQL, Scorecard, and pull-request dependency review were not executed against
this uncommitted checkout. Their workflow definitions passed static checks;
their hosted analysis results remain separate from this local validation.
The portal's CMake configuration still reports unused `BUILD_TESTING` and
`CMAKE_EXPORT_NO_PACKAGE_REGISTRY` variables injected by nixpkgs' generic setup
hook. The project has no CTest suite or package export. Broadly disabling CMake
warnings would hide useful diagnostics, so that upstream setup message remains.
The system profile also reports overlapping Xorg/Xwayland protocol and manual
pages, plus Gawk's unindexed `gawknotes.info`. These upstream documentation
messages do not represent executable collisions. They remain visible rather
than introducing package forks or disabling collision diagnostics for them.

Use `nix develop --command prek run --all-files` in each repository for the
local hooks. Run `gitleaks git --redact --no-banner` from each repository to
scan history. The root CI also runs submodule hooks and history scans.

Heavy local checks share `/tmp/nix-conf-heavy-work.lock`. Run one Nix check
attribute per process with `--max-jobs 1 --cores 2 --option eval-cores 1` and
`CARGO_BUILD_JOBS=2`; separate processes release evaluator memory between
checks. Monitor available memory as well as evaluator RSS. These flags limit
parallel work, not evaluator memory. Full desktop closures must be built on
`desktop`, as specified in `AGENTS.md`.

References: [Gitleaks configuration](https://github.com/gitleaks/gitleaks#configuration),
[Rustup overrides](https://rust-lang.github.io/rustup/overrides.html),
[Yamlfmt configuration](https://github.com/google/yamlfmt/blob/main/docs/config-file.md),
[RSA advisory](https://rustsec.org/advisories/RUSTSEC-2023-0071.html).
