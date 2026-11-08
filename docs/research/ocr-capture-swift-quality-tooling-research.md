# OCR Capture Swift quality tooling research

Research date: 2026-09-02

## Recommendation

Use one tool for each job. The useful baseline is:

1. Swift compiler diagnostics in both supported language modes.
2. `swift-format` as the only formatter.
3. SwiftLint with a small correctness and performance rule set.
4. Periphery for unused declarations and imports.
5. Unit tests under Address Sanitizer and Thread Sanitizer in separate, slower checks.
6. CodeQL on a macOS runner with the macOS 26 SDK.
7. Existing nixfmt, Statix, deadnix, and flake checks for the Nix packaging.

Do not enable every SwiftLint rule or add a second Swift formatter. That creates
noise, style conflicts, and eventually a baseline file full of ignored defects.
The compiler and tests should run first because SwiftLint expects compilable
source.[^swiftlint-setup]

## What the repository has now

The OCR package is a macOS 14 SwiftPM executable with no third-party Swift
dependencies. Its Nix build uses Swift 5.10.1 today and already passes
`-strict-concurrency=complete`. The local Xcode toolchain is Swift 6.3.3 with
the macOS 26 SDK. The package therefore needs two deliberate compilation lanes:

| Lane | Purpose | Required flags |
| --- | --- | --- |
| Nix Swift 5.10 | Shipping compatibility and legacy Vision backend | `-swift-version 5 -strict-concurrency=complete -warnings-as-errors -D OCR_CAPTURE_NIX_BUILD` |
| Xcode Swift 6 | Current language mode and macOS 26 document backend | `-swift-version 6 -strict-concurrency=complete -warnings-as-errors -D OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION` |
| Xcode Swift 6 legacy branch | Prove the conditional fallback has not rotted | Swift 6 flags plus `-D OCR_CAPTURE_NIX_BUILD`, without the document feature define |

Swift 5.10 reports complete concurrency problems as warnings. Swift 6 language
mode makes data-race safety violations errors, so warnings-as-errors is needed
to make the Swift 5 lane equally strict.[^swift-510][^swift-6] Swift's compiler
defines `-warnings-as-errors` as the option that promotes all warnings.[^swift-options]

Use these flags on the application sources and tests. A passing optimized Nix
binary alone does not type-check test-only code.

For SwiftPM, the portable commands are:

```console
swift test \
  -Xswiftc -swift-version -Xswiftc 5 \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors

swift test \
  -Xswiftc -swift-version -Xswiftc 6 \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
```

The package manifest can express complete checking to Swift 5.10 with
`.enableExperimentalFeature("StrictConcurrency=complete")`. Keep the command-line
flags in the Nix derivation as the final enforcement point. PackageDescription's
typed `.treatAllWarnings(as: .error)` setting requires PackageDescription 6.2,
so it cannot replace the flags while the manifest remains at tools version
5.10.[^warning-api]

On Swift 6.2 or newer, add a non-default audit lane with
`-strict-memory-safety -warnings-as-errors`. Strict memory safety makes unsafe
constructs visible rather than banning necessary unsafe code. Each legitimate
use must become explicit and reviewable.[^strict-memory] Do not send this flag
to the Swift 5.10 compiler, which does not implement it.

## Formatting

Use the Swift project's Xcode-bundled `swift-format` for both formatting and the
read-only check:

```console
xcrun swift-format format --configuration .swift-format --recursive --in-place Sources Tests
xcrun swift-format lint --configuration .swift-format --strict --parallel --recursive Sources Tests
```

Commit a `.swift-format` file inside the OCR package and pass it explicitly in
Nix checks. The tool otherwise searches parent directories, which makes the
result depend on where it runs. `--strict` gives warnings a failing exit status,
and omitting `--ignore-unparsable-files` makes parser failures fail the
check.[^swift-format]

The current nixpkgs formatter identifies itself as 508.0.0 while its derivation
version is 5.10.1. It does not parse Swift 6.2's `unsafe` expression syntax,
including inside inactive conditional-compilation branches. The local Xcode
formatter is 6.3.0 and does parse it. Run Xcode's formatter on macOS 26 rather
than weakening the strict-memory-safety audit or making the package conform to
an obsolete parser. Upstream notes that Swift 5.8 and newer formatters are
decoupled from the compiler, but an old formatter still may not understand later
syntax.[^swift-format]

Do not also run Nick Lockwood's SwiftFormat. Two formatters with different
layout rules will rewrite each other's output.

## SwiftLint

Run SwiftLint with the same toolchain used for compilation. Some rules use
SourceKit, and upstream explicitly requires matching the compiler
toolchain.[^swiftlint-toolchain]

```console
swiftlint lint \
  --strict \
  --no-cache \
  --config .swiftlint.yml \
  Sources Tests
```

Use default rules plus these opt-in groups:

- Safety and concurrency: `force_unwrapping`,
  `implicitly_unwrapped_optional`, `incompatible_concurrency_annotation`,
  `redundant_sendable`, `unhandled_throwing_task`,
  `unowned_variable_capture`, and `weak_delegate`.
- Resource and lifecycle mistakes: `discarded_notification_center_observer`,
  `private_action`, `private_outlet`, `overridden_super_call`, and
  `prohibited_super_call`.
- Performance traps: `contains_over_filter_count`,
  `contains_over_filter_is_empty`, `empty_count`, `empty_string`,
  `first_where`, `last_where`, `reduce_into`, and `sorted_first_last`.
- Low-ambiguity maintainability checks: `async_without_await`, `attributes`,
  `fatal_error_message`, `modifier_order`, `number_separator`,
  `prefer_self_in_static_references`, `test_case_accessibility`,
  `unavailable_function`, and `unused_parameter`.

Keep formatter-owned layout rules disabled where the tools disagree. Do not use
`opt_in_rules: all`; SwiftLint marks rules opt-in when they are slow, lack broad
consensus, or produce false positives.[^swiftlint-rules]

Set `strict: true`, keep `allow_zero_lintable_files: false`, and do not create a
baseline. A baseline would hide newly introduced code in a package small enough
to clean up directly. Reasonable starting limits for this codebase are 140/180
characters for line warning/error, 700/800 lines per file, and 500/600 lines per
type. Complexity warnings should trigger refactoring, but keep the initial error
threshold above existing parsing and document-conversion code until those
functions have been split.

SwiftLint's type-aware `analyze` command is useful for `unused_import` and
`unused_declaration`, but it needs the exact log from a clean, non-incremental
compiler invocation and is much slower.[^swiftlint-analyze] Do not pretend a
normal `swiftlint lint` invocation ran analyzer rules. Either add a dedicated
clean-build analyzer check with a captured compiler log or let Periphery own
unused-code checking.

## Unused-code checking

Periphery is the better whole-package unused-code check. It builds every SwiftPM
target, reads the compiler index store, and constructs a reference graph.[^periphery]
For this AppKit executable, retain declarations reachable through the Objective-C
runtime:

```console
periphery scan \
  --project-root . \
  --clean-build \
  --retain-objc-accessible \
  --strict \
  --disable-update-check \
  --relative-results
```

Run the command in an ephemeral Nix build directory because `--clean-build`
removes build artifacts. Do not use `--retain-public`; this is an executable,
not a library whose public declarations need to be preserved for unknown
clients. Review any AppKit callback false positive before adding a narrow
`periphery:ignore` comment.

Conditional source exists in two programs as far as an indexer is concerned.
Run Periphery once with the legacy feature flags and again on a Swift 6/macOS 26
runner with document recognition enabled. A legacy-only scan cannot prove that
the document adapter is live.

## Runtime checks

Run the sanitizers separately in debug mode:

```console
swift test --sanitize=address
swift test --sanitize=thread
```

Address Sanitizer detects invalid memory access. Thread Sanitizer detects races
that tests actually exercise. Apple reports roughly 2 to 5 times runtime and 2
to 3 times memory overhead for Address Sanitizer, and 2 to 20 times runtime and
5 to 10 times memory overhead for Thread Sanitizer.[^apple-sanitizers] Running
both on every keystroke is wasteful; exported flake checks or pre-push hooks are
a better fit. SwiftPM supports both sanitizer forms directly.[^swift-sanitizers]

Also run tests with `-enable-actor-data-race-checks` in the Swift 5 lane. This
adds dynamic actor-isolation checks at boundaries the older compiler cannot
fully prove. Keep it out of the release binary.

The Main Thread Checker matters for AppKit, but the package's noninteractive
unit tests do not exercise screen permission prompts, overlays, pasteboard
timers, or review-window callbacks. Add a signed, interactive smoke test on a
Mac with Screen Recording permission. Apple supports injecting the checker into
an existing macOS executable, but that test cannot be a hermetic Nix build.[^apple-sanitizers]

UBSan is not a Swift check. Apple documents Swift support for Address and Thread
Sanitizers but restricts Undefined Behavior Sanitizer to C-family code.[^apple-sanitizers]

## Security analysis

Add Swift to the existing CodeQL workflow as a separate macOS job. CodeQL's
current Swift extractor supports Swift 5.4 through 6.3, requires macOS, and does
not support Embedded Swift.[^codeql-support] This package is inside a nested
directory and needs a particular feature define, so use manual build mode:

```yaml
- uses: github/codeql-action/init@<full-commit>
  with:
    languages: swift
    build-mode: manual
- run: >-
    swift build
    --package-path pkgs/by-name/oc/ocr-capture
    --arch arm64
    -Xswiftc -warnings-as-errors
- uses: github/codeql-action/analyze@<same-full-commit>
```

Use a runner with the macOS 26 SDK so CodeQL observes
`RecognizeDocumentsRequest`. GitHub supports `swift build` in manual Swift
analysis and recommends compiling one architecture.[^codeql-build] Keep CodeQL
outside the Nix derivation. It traces a real compilation, needs macOS, and is a
CI security service rather than a reproducible package-build input.

Semgrep's Swift support is generally available, but its useful Swift security
rules are mainly in the Pro engine.[^semgrep-swift] Do not add a generic
`semgrep --config=auto` gate merely to increase the checker count. Add Semgrep
later only for named project policies, such as forbidding networking or process
execution outside an approved file.

The Swift package currently has no external dependencies and no
`Package.resolved`, which is better than any advisory scanner result. If that
changes, add both:

- Dependabot with `package-ecosystem: swift` at
  `/pkgs/by-name/oc/ocr-capture`. GitHub supports Swift 5 and 6 version and
  security updates.[^dependabot]
- OSV-Scanner 2.4 or newer in a networked CI audit. Version 2.4 enabled the
  `swift/packageresolved` extractor by default.[^osv-swift]

Do not put OSV lookups in the hermetic Nix build. Without a pinned offline
database, the answer changes as advisories are published.

## Nix wiring

Put deterministic package checks close to the package and host-toolchain checks
in macOS development and CI lanes:

- Include `.swift-format`, `.swiftlint.yml`, and any Periphery configuration in
  the package fileset.
- Run compiler warnings-as-errors and the binary self-test in the hermetic Nix
  derivation. Run the Xcode formatter, SwiftLint, Periphery, and SwiftPM tests in
  macOS development hooks or exported CI checks. SwiftLint's SourceKit-backed
  rules cannot load Apple's private SourceKit framework in a Nix sandbox, so
  disabling those rules there would provide misleadingly weaker coverage.
- Export Address Sanitizer and Thread Sanitizer as separate Darwin-only flake
  checks so `nix flake check --keep-going` reports each result independently.
- Keep the Swift 6/macOS 26 check and CodeQL on a runner whose Xcode supplies
  that SDK. Nix's current Swift 5.10 SDK cannot type-check unavailable Vision
  declarations.

Nixpkgs runs `checkPhase` only when `doCheck` is enabled.[^nix-check-phase]
`nix flake check` builds derivations exported under `checks` and supports
`--keep-going`, which makes it the right top-level entry point.[^flake-check]

The nested `nixpkgs-personal` repository already uses nixfmt, Statix, deadnix,
and nixf diagnostics through treefmt. Keep those checks and make sure the OCR
package paths are included. Run at least:

```console
nixfmt --check pkgs/by-name/oc/ocr-capture/package.nix
statix check pkgs/by-name/oc/ocr-capture/package.nix
deadnix --fail pkgs/by-name/oc/ocr-capture/package.nix
nix flake check --keep-going
```

## Current tool availability

The pinned nixpkgs used for this research exposes these aarch64-darwin packages:

| Tool | nixpkgs version |
| --- | --- |
| Swift | 5.10.1 |
| swift-format | 5.10.1 derivation, binary reports 508.0.0 |
| SwiftLint | 0.65.0 |
| Periphery | 3.8.0 |
| CodeQL | 2.26.3 |
| Semgrep | 1.172.0 |
| OSV-Scanner | 2.5.0 |
| nixfmt | 1.4.0 |
| deadnix | 1.3.2 |
| Statix | 0.5.8 unstable snapshot dated 2026-07-17 |

The minimal blocking set is compiler checks, official formatting, curated
SwiftLint, Periphery, tests, and the Nix checks. Add sanitizer lanes and CodeQL
before merging. OSV-Scanner and Dependabot become useful only when the Swift
package gains a dependency.

[^swiftlint-setup]: [SwiftLint setup and execution model](https://github.com/realm/SwiftLint/blob/main/README.md#setup)
[^swift-510]: [Swift 5.10 release: complete concurrency checking](https://www.swift.org/blog/swift-5.10-released/)
[^swift-6]: [Announcing Swift 6: data-race safety](https://www.swift.org/blog/announcing-swift-6/)
[^swift-options]: [Swift compiler diagnostic-control options](https://github.com/swiftlang/swift/blob/main/include/swift/Option/Options.td)
[^warning-api]: [PackageDescription `treatAllWarnings(as:)`](https://docs.swift.org/swiftpm/documentation/packagedescription/swiftsetting/treatallwarnings%28as%3A_%3A%29/)
[^strict-memory]: [SE-0458: opt-in strict memory safety](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md)
[^swift-format]: [swift-format usage, configuration, and version matching](https://github.com/swiftlang/swift-format/blob/main/README.md)
[^swiftlint-toolchain]: [SwiftLint: working with multiple Swift versions](https://github.com/realm/SwiftLint/blob/main/README.md#working-with-multiple-swift-versions)
[^swiftlint-rules]: [SwiftLint rule configuration and opt-in policy](https://github.com/realm/SwiftLint/blob/main/README.md#rules)
[^swiftlint-analyze]: [SwiftLint full-AST analysis requirements](https://github.com/realm/SwiftLint/blob/main/README.md#analyze)
[^periphery]: [Periphery's index-store analysis and Objective-C retention](https://github.com/peripheryapp/periphery#how-it-works)
[^apple-sanitizers]: [Apple: diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)
[^swift-sanitizers]: [Swift.org: LLVM Thread and Address Sanitizers](https://www.swift.org/documentation/server/guides/llvm-sanitizers.html)
[^codeql-support]: [CodeQL supported languages and frameworks](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
[^codeql-build]: [GitHub: building Swift for CodeQL](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages#building-swift)
[^semgrep-swift]: [Semgrep Swift general availability](https://semgrep.dev/products/product-updates/swift-ga/)
[^dependabot]: [GitHub Dependabot supported ecosystems](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#swift)
[^osv-swift]: [OSV-Scanner 2.4 release notes](https://github.com/google/osv-scanner/releases/tag/v2.4.0)
[^nix-check-phase]: [Nixpkgs manual: check phase](https://nixos.org/manual/nixpkgs/unstable/#ssec-check-phase)
[^flake-check]: [Nix reference: `nix flake check`](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake-check)
