# Finder Favorites quality tooling research

Research date: 2026-09-02

## Scope

The maintained files under `pkgs/by-name/fi/finder-favorites` use Swift, C,
Nix, Bash, YAML, JSON, and Markdown. The package is Darwin-only. Its pinned
nixpkgs currently supplies Swift 5.10.1 and Clang 21.1.8 on
`aarch64-darwin`. The developer Mac has Apple Swift 6.3.3 and the macOS 26
SDK.

That version split should be deliberate. Nix Swift 5.10 is the shipping
contract. Apple Swift 6 is a forward-compatibility audit. A check that silently
uses whichever Xcode happens to be selected is not reproducible.

## Recommended gate set

| Files | Format | Static checks | Executed checks |
| --- | --- | --- | --- |
| Swift and `Package.swift` | pinned `swift-format` | Swift compiler, strict concurrency, SwiftLint, Periphery | XCTest, release self-test, ASan, TSan |
| C and header | `clang-format` | strict Clang warnings, Clang Static Analyzer, `clang-tidy` | bridge tests where no live Finder mutation occurs, ASan and UBSan where C paths are exercised |
| `package.nix` | official `nixfmt` | Statix, deadnix, nixf diagnostics | Nix evaluation, build, install checks, reproducibility spot-check |
| Bash | `shfmt` | `bash -n`, ShellCheck | run the quality script in the Nix development shell |
| YAML | `yamlfmt` | `yamllint --strict` plus each owning tool | SwiftLint, clang-format, clang-tidy, and Periphery must load their own configs |
| JSON | pinned Prettier | `jq -e .` plus `swift-format` config loading | the formatter must lint a real Swift file with the config |
| Markdown | `rumdl fmt` | `rumdl check`, `typos` | offline local-link checks only when local links exist |

Use the repository's existing treefmt programs for Nix, Bash, YAML, JSON, and
Markdown. Do not install competing formatters for the same file type.

## Swift compiler and package checks

Compile every production and test target in Swift 5 language mode with:

```console
swift build \
  --explicit-target-dependency-import-check error \
  -Xswiftc -swift-version -Xswiftc 5 \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors \
  -Xcc -std=c17
```

`-strict-concurrency=complete` makes Swift 5.10 diagnose possible data races.
Those diagnostics are warnings in Swift 5.10, so `-warnings-as-errors` is part
of the contract, not cosmetic strictness.[^swift-510] SwiftPM 5.10 also
supports `--explicit-target-dependency-import-check`; setting it to `error`
catches imports that were omitted from a target's declared dependencies.[^swiftpm-build]

Run `swift package dump-package` before compilation to fail quickly on an
invalid manifest. Run the XCTest target with the same compiler and C flags.
The Nix Swift distribution in this repository omits XCTest, so the hermetic
derivation should retain its release-built in-memory self-test. Run XCTest in
the Apple-toolchain development check. This is a packaging limitation, not a
reason to stop type-checking test code.

Add a separate Apple Swift 6 audit with its own scratch directory:

```console
swift build \
  --scratch-path .build/swift-6 \
  --explicit-target-dependency-import-check error \
  -Xswiftc -swift-version -Xswiftc 6 \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
```

Do not reuse artifacts between Swift 5 and Swift 6 lanes.

Apple Swift 6.2 and newer also has `-strict-memory-safety`. It inventories C
interop, unsafe pointer use, `Unmanaged`, and other constructs that Swift
cannot prove safe.[^strict-memory] This project should run it as a reviewed
audit because the bridge is intentionally unsafe. It cannot yet be the
shipping gate. The `unsafe` acknowledgements used to resolve those warnings
are Swift 6.2 syntax and the shipping Swift 5.10 parser cannot read them.

### Swift formatting

Use the standalone Nix-pinned `swift-format` executable:

```console
swift-format lint \
  --configuration .swift-format \
  --parallel \
  --recursive \
  --strict \
  Sources Tests Package.swift
```

`swift format` is bundled only with Swift 6. The standalone formatter is the
portable command for the Swift 5.10 development environment. `--strict` makes
format warnings fail, and leaving out `--ignore-unparsable-files` makes syntax
failures visible.[^swift-format]

The pinned derivation is named `swift-format-5.10.1`, although its binary
reports 508.0.0. It parses the package's current Swift 5.10 source. Record this
version mismatch in check output and do not alternate it with Xcode 6.3's
formatter. Two formatter versions can produce different source from the same
input.

### SwiftLint

Make SwiftLint required rather than conditional:

```console
swiftlint lint --no-cache --strict --config .swiftlint.yml
```

Set `check_for_updates: false`, keep `strict: true`, and keep
`allow_zero_lintable_files: false`. SwiftLint otherwise checks for new releases
by default, which is inappropriate inside a Nix-backed quality command. It
uses SourceKit for some rules and upstream requires the same Swift toolchain as
the compiler.[^swiftlint]

Keep the default rule set and add a curated set of low-noise checks. The useful
additions for this command-line tool are:

- `anonymous_argument_in_multiline_closure`
- `async_without_await`
- `contains_over_filter_is_empty`
- `contains_over_range_nil_comparison`
- `direct_return`
- `discouraged_optional_boolean`
- `empty_collection_literal`
- `fatal_error_message`
- `force_unwrapping`
- `implicitly_unwrapped_optional`
- `incompatible_concurrency_annotation`
- `reduce_into`
- `redundant_sendable`
- `sorted_first_last`
- `unhandled_throwing_task`
- `unowned_variable_capture`
- `unused_parameter`

Do not enable every opt-in rule. SwiftLint explicitly reserves opt-in status
for rules that may be slow, noisy, or not broadly agreed upon.[^swiftlint]
Keep layout rules owned by `swift-format` disabled in SwiftLint.

The current `analyzer_rules: unused_import` setting does nothing during
`swiftlint lint`. Analyzer rules require `swiftlint analyze`, an exact log from
a clean, non-incremental compiler invocation, and a matching SourceKit.[^swiftlint-analyze]
Either add that complete lane or remove the setting so the configuration does
not claim coverage it lacks.

### Periphery

Run Periphery as the dead-code check:

```console
periphery scan --config .periphery.yml
```

Periphery builds all SwiftPM targets, consumes the compiler index store, and
constructs a declaration reference graph.[^periphery] Keep `strict: true`,
`disable_update_check: true`, `retain_codable_properties: true`, and
`retain_equatable_properties: true`.

There is an interface decision to settle. If `FinderFavoritesCore` remains a
published library product, retain public declarations. If it exists only to
separate the CLI and tests, remove the library product, use Swift's package
access where cross-target access is needed, and let Periphery report unused
public declarations. Retaining every public declaration otherwise hides dead
code.

Periphery can report false unused imports around C and Objective-C modules.
Disable its unused-import analysis for this mixed package, or retain the named
bridge module after confirming a narrow suppression works. Let a properly
wired SwiftLint analyzer lane own unused imports.

## C bridge

Declare `cLanguageStandard: .c17` in `Package.swift`. Use one pinned Clang
version for compilation, formatting, tidy checks, and static analysis. The
current nixpkgs Clang and `clang-tools` are both 21.1.8.

For this single translation unit, a pinned `-Weverything -Werror` audit is
manageable. Clang generally advises against `-Weverything`, so its use depends
on the compiler remaining pinned.[^clang-warnings] The four broad exclusions
found necessary on this code are:

```text
-Wno-poison-system-directories
-Wno-declaration-after-statement
-Wno-implicit-void-ptr-cast
-Wno-padded
```

The first is caused by the Nix Darwin SDK wrapper. The next two reject valid
C17 and idiomatic C allocation code. Structure padding is an ABI observation,
not a defect in these private structures. Keep the unavoidable CoreFoundation
qualifier cast suppression on the smallest source region. Do not suppress
switch completeness, nullability, ownership, format, conversion, or prototype
diagnostics.

Format both files with one committed `.clang-format` and enforce it read-only:

```console
clang-format --dry-run --Werror --style=file \
  Sources/FinderFavoritesBridge/FinderFavoritesBridge.c \
  Sources/FinderFavoritesBridge/include/FinderFavoritesBridge.h
```

Clang documents `--dry-run` and `--Werror` for a non-mutating CI check.[^clang-format]

Run `clang-tidy` with the exact SDK, deployment target, include path, and C
standard used by SwiftPM. Enable `clang-analyzer-*`, `bugprone-*`, `cert-*`,
`concurrency-*`, `performance-*`, and `portability-*`, then promote all
findings to errors. The current bridge needs narrow exclusions for
`bugprone-easily-swappable-parameters` and
`bugprone-multi-level-implicit-pointer-conversion`. Do not add readability or
style groups that compete with clang-format. Clang-tidy accepts compiler flags
after `--`, which is preferable to inventing an incomplete compilation
database for one C file.[^clang-tidy]

Also run the Clang Static Analyzer directly on the C translation unit. It is
path-sensitive and includes CoreFoundation retain and release checking.[^clang-analyzer]
Direct analysis is more reliable here than `scan-build`, whose compiler
interposition can miss SwiftPM's actual C invocation. Static Analyzer and
clang-tidy overlap, but each has checks the other does not run by default.

Add nullability annotations to every pointer in the public bridge header and
enable nullability-completeness warnings. This improves Swift's imported types
and makes ownership boundaries reviewable. Document which returned pointers
are borrowed and which caller frees.

## Runtime tests and sanitizers

Run debug XCTest under Address Sanitizer and Thread Sanitizer in separate
scratch directories:

```console
swift test -c debug --scratch-path .build/asan --sanitize address
swift test -c debug --scratch-path .build/tsan --sanitize thread
```

Apple documents ASan for invalid memory access and TSan for data races. It also
notes that UBSan supports C-family code, not Swift.[^apple-sanitizers] Never
combine ASan and TSan in one binary. Do not ship sanitizer runtimes.

The normal in-memory suite does not call the live CoreServices bridge. ASan
therefore covers the Swift planner and transaction engine but cannot prove the
C bridge correct. Use static analysis for the bridge, and add pure C helper
tests when bridge logic can be separated from `LSSharedFileList`. A live
Finder write is not safe in a Nix build or unattended CI.

Run complete sanitizer suites without XCTest filters. A current SwiftPM issue
documents a macOS code-signing failure for filtered sanitized tests.[^swiftpm-sanitizer]

## Nix, Bash, and configuration files

The repository already has the right Nix checks. Apply them to `package.nix`:

```console
nixfmt --check package.nix
statix check package.nix
deadnix --fail package.nix
nix flake check --no-write-lock-file --keep-going
```

Nixfmt is the official formatter.[^nixfmt] Statix and deadnix work on syntax
trees and cannot replace evaluation.[^statix][^deadnix] A successful package
build and install check remain the real type and integration check for this
dynamically typed build language. Keep `strictDeps = true`, `doCheck = true`,
and `doInstallCheck = true`; Nixpkgs documents install checks as validation of
the installed output.[^nixpkgs-checks]

Use `nix build --rebuild` as a periodic reproducibility spot-check. Nix rebuilds
the derivation and compares its result with the existing store path.[^nix-repro]
It is too expensive for every save.

Check `Scripts/check-quality.sh` with:

```console
bash -n Scripts/check-quality.sh
shellcheck --shell=bash --severity=style Scripts/check-quality.sh
shfmt -d -i 2 -ci -sr Scripts/check-quality.sh
```

ShellCheck performs Bash static analysis but does not format code, which is why
shfmt remains necessary.[^shellcheck][^shfmt] The quality script should fail
with a clear error if a required tool is absent. Optional `command -v` guards
turn missing coverage into a successful check.

Keep yamlfmt and strict yamllint for all four YAML configs. Generic YAML tools
can catch duplicate keys, indentation, and syntax, but cannot validate
SwiftLint or Clang option names.[^yamllint] Each owning tool must load its
configuration during the same check. Use the repository's pinned Prettier for
`.swift-format`, then validate JSON syntax with `jq -e .` and semantics by
passing the file to `swift-format`. Prettier's `--check` is read-only and has a
failing exit status when formatting differs.[^prettier]

Use the existing rumdl and typos checks for `README.md`. Rumdl supplies both a
Markdown linter and `fmt --check`, while typos is designed for low false-positive
source spelling checks.[^rumdl][^typos] Do not add markdownlint-cli2 or CSpell
on top. They duplicate policy and add two more configuration vocabularies.

Do not make network link validation part of the Nix derivation. Lychee's
offline mode checks only local links, and the package README currently has no
links.[^lychee] Add a scheduled network-enabled job only if the documentation
later gains external references.

## Placement and CI safety

- Put compiler warnings, the release self-test, binary architecture, minimum
  OS, dependency, and signature checks in the hermetic package derivation.
- Put pinned formatter, linter, YAML, JSON, Markdown, Nix, and Bash checks in
  treefmt and pre-commit. Run the complete suite again in a flake check.
- Put XCTest, Swift 6, Periphery, ASan, TSan, and any SourceKit-backed analyzer
  on an `aarch64-darwin` pre-push or CI lane. Give every compiler mode and
  sanitizer a separate scratch directory.
- Disable update checks, caches that escape the build directory, remote config
  URLs, and package plugins. No quality check needs network access.
- Add CodeQL only as a separate macOS CI service if this repository is hosted
  where code scanning is available. Swift analysis requires macOS and a real
  compiled build.[^codeql] It is not a Nix build input.

This set is intentionally finite. One formatter per syntax, compiler errors as
the type gate, two independent C analyzers, and executed tests under runtime
instrumentation cover real failure modes without turning style preferences
into the majority of CI output.

[^swift-510]: [Swift 5.10 release notes on complete concurrency checking](https://www.swift.org/blog/swift-5.10-released/)
[^swiftpm-build]: [SwiftPM build command reference](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftBuild.md)
[^strict-memory]: [SE-0458: opt-in strict memory safety](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md)
[^swift-format]: [swift-format compatibility, lint, and configuration](https://github.com/swiftlang/swift-format/blob/main/README.md)
[^swiftlint]: [SwiftLint setup, toolchain matching, rules, and configuration](https://github.com/realm/SwiftLint/blob/main/README.md)
[^swiftlint-analyze]: [SwiftLint full-AST analyzer requirements](https://github.com/realm/SwiftLint/blob/main/README.md#analyze)
[^periphery]: [Periphery analysis model and SwiftPM support](https://github.com/peripheryapp/periphery)
[^clang-warnings]: [Clang user manual warning policy](https://clang.llvm.org/docs/UsersManual.html)
[^clang-format]: [ClangFormat command reference](https://clang.llvm.org/docs/ClangFormat.html)
[^clang-tidy]: [Clang-tidy checks and compiler argument handling](https://clang.llvm.org/extra/clang-tidy/index.html)
[^clang-analyzer]: [Clang Static Analyzer and command-line use](https://clang.llvm.org/docs/ClangStaticAnalyzer.html)
[^apple-sanitizers]: [Apple: diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)
[^swiftpm-sanitizer]: [SwiftPM macOS filtered-sanitizer issue](https://github.com/swiftlang/swift-package-manager/issues/9546)
[^nixfmt]: [Nixfmt, the official Nix formatter](https://github.com/NixOS/nixfmt)
[^statix]: [Statix architecture and checks](https://github.com/oppiliappan/statix)
[^deadnix]: [Deadnix command and callPackage handling](https://github.com/astro/deadnix)
[^nixpkgs-checks]: [Nixpkgs install check phase](https://nixos.org/manual/nixpkgs/unstable/#ssec-installCheck-phase)
[^nix-repro]: [Nix reproducibility spot-checks](https://nix.dev/manual/nix/stable/advanced-topics/diff-hook.html)
[^shellcheck]: [ShellCheck command reference](https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md)
[^shfmt]: [shfmt command reference](https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd)
[^yamllint]: [yamllint rules and configuration](https://yamllint.readthedocs.io/en/stable/)
[^prettier]: [Prettier CLI checks and exit codes](https://prettier.io/docs/cli)
[^rumdl]: [Rumdl linting and formatting](https://github.com/rvben/rumdl)
[^typos]: [Typos source-code spelling checks](https://github.com/crate-ci/typos)
[^lychee]: [Lychee local and network link checking](https://github.com/lycheeverse/lychee)
[^codeql]: [CodeQL Swift platform and build requirements](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
