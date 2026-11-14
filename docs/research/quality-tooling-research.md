# Quality tools and maintained language coverage

Reviewed: 2026-10-11. Scope: the root repository and its four initialized
submodules. Findings include the existing working tree, rather than HEAD alone.

## Answer

Keep the existing Nix, Python, TypeScript and shell quality stack. The concrete
improvements are source discovery, consistent versions between formatter and
compiler consumers, and checks for languages that previously relied on a single
fixture or a native application build. This audit remains incomplete until the
queued checks run and their findings are resolved.

Use released tooling with reproducible locks. A latest upstream release and the
latest tested Nixpkgs channel are different versions. The updated development
partition does not make every bundled tool the latest upstream release.

## Language coverage and decisions

| Language or format | Existing tools and validation | Changes and remaining work |
| --- | --- | --- |
| Nix | Official nixfmt, deadnix, Statix, nixf diagnostics, module evaluation, generated-output tests | Keep these complementary checks. Development nixpkgs and treefmt-nix pins were updated. |
| Python | Ruff lint and format, ty, compileall, pytest, Hypothesis, generated helper checks | Pin Ruff's language target to Python 3.14. Align hook and CI syntax coverage, including host, library, overlay, template, site and CI sources. |
| JavaScript and TypeScript | Strict TypeScript, type-aware Oxlint, Prettier, Node tests, package integration checks | Upgrade the root and four maintained package tooling bundles. Include `.mts` and `.cts` in treefmt. Share the locked Prettier binary between npm and treefmt. Run the compiler in the root hook. Enable type-aware editor configuration in owning projects. |
| Bash | shfmt, ShellCheck, checked Nix writers, generated-program and command tests | Retain source-template and rendered-program validation. Global suppression of unknown template variables does not replace rendered checks. |
| Rust | Submodule rustfmt, Cargo checks, Clippy with warnings denied, tests, cargo-deny, cargo-vet, fuzz checks | Keep the owning repositories' gates. Remove the root rustfmt entry, which has no owned Rust source after submodule exclusions. Toolchain upgrades require compiler and native check alignment. |
| Swift | swift-format and native SDK/compiler checks | Discover every Swift source under modules and tests in the standalone formatting check, matching the hook. Native compilation still requires Darwin for AppKit/CoreText sources. |
| C and C++ | clang-format, compiler warnings, package and VM regression builds | Keep checks using actual headers and compiler definitions. Broader static analysis with a compilation database remains a follow-up. |
| CMake | cmake-format and native CMake package checks | Keep package-owned build validation. |
| Lua | StyLua, checked mpv writer, runtime fixture | Add Luacheck coverage for all maintained Lua sources under modules and tests. Restrict application globals by path. |
| Nushell | nufmt, rendered `nu-check` writer, import and rejection fixtures | Keep parsing rendered templates without executing operational actions. |
| AWK | GNU awk parser and pretty-printer, command behavior tests | Keep syntax validation separate from executing scripts. |
| Tcl and Expect | tclfmt and tclint | Retain the supported CLI. The installed 0.9.0 lacks the main-branch documentation's `--no-check-style` flag. |
| Dart | dart format and Moonfin regression fixture | Add a standalone x86 Linux check of the assembled fixture with fatal informational diagnostics and strict casts, inference and raw types before executing it. The source fixture has an intentional method-substitution marker. |
| PHP | FreshRSS native integration tests | Add PHP syntax checking and PHP-CS-Fixer with risky transformations disabled. Add PHPStan at level 8 with real FreshRSS symbol discovery. Its diagnostics remain unvalidated. |
| PowerShell | Parser, PSScriptAnalyzer, generated guest checks and rejection fixtures | Keep the writer's explicit rule and interpreter policy. |
| SQL | PostgreSQL and SQLite formatting, real database/bootstrap fixtures | Keep dialect-specific formatting and execution tests. SQLFluff is a candidate only after reviewing its diagnostic value and formatter conflicts. |
| YAML and GitHub Actions | yamlfmt, yamllint, actionlint, pinact, Zizmor | Keep syntax, schema, expression, pinning and workflow-security checks. |
| TOML | Taplo and syntax checks | Keep repository and Cargo configuration validation. |
| JSON, CSS, HTML and XML | Prettier, syntax/schema checks, Stylelint, GTK CSS parser, xmllint, rendered artifact tests | Scope standalone web CSS checks to root-owned directories. GTK CSS templates need their native parser, rather than web CSS rules. |
| Markdown and spelling | rumdl, Typos, documentation build and relative-link checks | Keep linting even when formatting succeeds. Preserve reviewed evidence and literal command text. |

Partial source fragments and negative parser fixtures cannot use the same gate
as valid complete programs. Validate assembled programs and retain independent
failure fixtures. Each submodule owns its configuration; root exclusions do not
prove that the submodule's checks passed.

## Release research and selected versions

The updated root development nixpkgs revision is
`6510408d147d8c5e6d76043e899e9251756f6a75`, dated 2026-10-10. Its package
recipes declare Ruff 0.16.10, ty 0.0.84, rumdl 0.2.78, Typos 1.50.3,
Stylelint 17.14.1, StyLua 2.5.2 and yamllint 1.37.1.
These are source observations, not evidence of a successful build.
[Selected Nixpkgs source](https://github.com/NixOS/nixpkgs/tree/6510408d147d8c5e6d76043e899e9251756f6a75/pkgs).

The npm tooling updates select the current retrieved releases
[Oxlint 1.87.0](https://github.com/oxc-project/oxc/releases/tag/oxlint_v1.87.0),
[tsgolint 7.0.2004](https://github.com/oxc-project/tsgolint/releases/tag/v7.0.2004)
and [Prettier 3.9.10](https://github.com/prettier/prettier/releases/tag/3.9.10).
TypeScript already selects
[7.0.2](https://github.com/microsoft/TypeScript/releases/tag/v7.0.2).
The maintained bundles are the root, package-repository root, Feishin helpers,
homelab IoT scripts and T3 runtime checker. Their locks and Nix dependency hashes
were updated together. The Blueair manifest retains upstream development
metadata; changing it would require reviewing its upstream build contract.

Retrieved upstream releases ahead of the development channel include
[Ruff 0.17.0](https://github.com/astral-sh/ruff/releases/tag/0.17.0),
[ty 0.0.86](https://github.com/astral-sh/ty/releases/tag/0.0.86),
[rumdl 0.2.79](https://github.com/rvben/rumdl/releases/tag/0.2.79),
[Typos 1.51.1](https://github.com/crate-ci/typos/releases/tag/v1.51.1),
[Stylelint 17.16.0](https://github.com/stylelint/stylelint/releases/tag/17.16.0),
[StyLua 2.6.0](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.6.0)
and [yamllint 1.38.0](https://github.com/adrienverge/yamllint/releases/tag/v1.38.0).
Do not describe the current implementation as using every latest release.

## Configuration evidence

Oxlint explicitly supports `options.typeAware` for editor integrations. CLI-only
type awareness can leave the editor using different analysis. A separate compiler
check retains TypeScript diagnostics while Oxlint runs lint rules.
[Oxlint type-aware configuration](https://oxc.rs/docs/guide/usage/linter/type-aware).

Ruff's `ALL` selection expands as releases add rules. Preview settings can change
formatting and diagnostics, so upgrades require reviewing actual findings rather
than adding blanket exceptions. The explicit language target matches the ty
project target.
[Ruff configuration](https://docs.astral.sh/ruff/configuration/),
[Ruff preview behavior](https://docs.astral.sh/ruff/preview/).

Luacheck supports path-specific globals and standards. Read-only globals preserve
checks against accidental mutation of the host API; the mpv test adapter is the
intentional exception because it supplies that API.
[Luacheck configuration](https://luacheck.readthedocs.io/en/stable/config.html).

Dart's strict casts, inference and raw-type modes are opt-in. Analyze the complete
assembled source so method references resolve against the actual reviewed patch.
[Dart analysis configuration](https://dart.dev/tools/analysis),
[Dart analyzer](https://dart.dev/tools/dart-analyze).

PHP's syntax-only CLI does not execute application code or establish semantic
correctness. PHP-CS-Fixer supports a checked-in rule configuration and risky-rule
control. PHPStan can discover external application symbols through scan paths;
application bootstrap files would execute code and are unsuitable here.
[PHP CLI syntax checking](https://www.php.net/manual/en/features.commandline.options.php),
[PHP-CS-Fixer configuration](https://cs.symfony.com/doc/config.html),
[PHPStan symbol discovery](https://phpstan.org/user-guide/discovering-symbols).

Current Oxfmt documentation recommends it as a dedicated formatter and describes
output differences. Retain Prettier until a trial checks all consumers, embedded
languages and editor settings. Older research statements about beta status
remain historical observations.
[Oxfmt documentation](https://oxc.rs/docs/guide/usage/formatter.html).

## Validation and limits

On x86_64 Linux, focused checks passed for all four maintained Lua sources with
Luacheck 1.2.0, all three maintained Swift sources with swift-format 6.2.4, and
the three FreshRSS PHP helpers plus their formatter configuration with PHP 8.4.26.
The modified Nix files parsed and formatted with nixfmt 1.5.0. The npm lock
prefetcher produced dependency hashes for all five updated tooling bundles.
These checks do not prove the new Nix derivations evaluate or build.

Full validation remains queued behind another workload under the required
desktop runner. The original root Python, JavaScript/TypeScript, stylesheet and Swift quality
derivations subsequently built successfully on x86 Linux. A full hook run,
shared tool-wrapper build, Dart assembled-fixture run, PHP formatter run,
Darwin compilation and activation remain unverified. A read-only review of the captured initial additions found no concrete
configuration defect; it identified PHP semantic analysis, release gaps and
unverified editor parity as unfinished requirements.

Complete the queued checks, resolve their diagnostics, validate PHPStan,
and decide whether the remaining upstream release gaps justify independent
package overrides before calling this audit complete.

## Submodule completion pass

The framework now owns Ruff, ty, Python syntax and standalone Python quality
checks for its documentation hook and selector fuzzer. Focused Ruff and ty checks
passed for both sources. The fuzzer records a string for its first selector and
now documents its helper functions. Its development-only Nixpkgs and treefmt
pins match the updated root development partition.

The secret-management submodule now schedules YAML and shell formatters before
their linters. A separate hook checks the independent Rust fuzz workspace's
formatting, and the nightly fuzz CI lane runs its Clippy check with warnings
denied. Its development tooling pins were updated. The manifest-selected Rust
1.97 lane and Nixpkgs compiler lane remain separate; no Rust 1.99 migration or
matching-version claim is made.

The package submodule's Python syntax inventory now includes its fuzz, site and
flake helpers. Its development-only pins were updated. Concurrent work also
expanded the compiler-project discovery manifest, Nix JavaScript source inputs,
and type-aware hook. These integration changes require fresh combined validation.

Homelab's Python syntax inventory now includes its module, fuzz, site, flake and
CI helpers. The broad unresolved Pillow import exception was removed because
Pillow is a declared checker dependency. PHPStan's shared hook and standalone
check use level 8 and scan the real pinned FreshRSS app, library and CLI symbols
without executing the application bootstrap. There is no ignored-error baseline.
PHPStan and PHP-CS-Fixer findings must still be run and fixed. Four unreadable credential/feed cases were reproduced as TypeErrors before the fix and now refuse the read explicitly. The four persistent regression tests passed under PHP 8.4.26 and pytest 9.1.1; PHP syntax checks also passed.

An earlier captured-source evaluation failed on a newly referenced Feishin source
absent from that capture, and on a development-input store path. The current
working tree includes the Feishin source. The failed capture is evidence of an
unsuccessful evaluation; it does not establish that the refreshed working tree
passes. Subsequent validation must use a fresh consistent source capture.
