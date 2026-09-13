# Technology review implementation

Implemented and checked on 2026-09-10, following the
[technology review](technology-stack-research.md). Keep nix-seal and the existing
NixOS, nix-darwin, Home Manager and flake-parts architecture. The reviewed
alternatives did not establish a reason to replace those foundations.

## Changes

| Area | Result |
| --- | --- |
| Dependency updates | Dependabot now includes the starter's Nix lock alongside the root and development flake. |
| JavaScript | Added an explicit Oxlint correctness policy, a pinned development-shell tool, a Git hook and the `javascript-quality` CI check for maintained probes under `tests`. |
| Editor integration | Selected the Oxc extension in both language modules, pointed it at the pinned Oxlint binary and required a repository config. This repository enables Oxlint and disables ESLint; Prettier remains its formatter. |
| Nix defaults | Removed six unused experimental feature defaults after searching their consumers. Retained flakes, the Nix CLI and the Linux UID/cgroup features used by this configuration. |
| Python tests | Added Hypothesis to the shared test and quality environments. Generated passwords exercise XML escaping, exact round trips, unrelated XML content and private credential permissions. |
| Native Swift tests | Added four parameterized Swift Testing tests covering 15 numeric option cases in OCR Capture. Existing XCTest cases remain. |
| nix-seal recovery | Added isolated CLI drills for cache-backup import, reconstruction with a separate recovery identity, signer rotation, stale-artifact rejection and explicit rollback to approved trust. |

Oxlint exposed a promise callback written as a conditional expression. The
callback now uses an explicit conditional with the same resolve/reject behavior.
The initial lint policy enables correctness rules; it does not turn every
stylistic or suspicious-code rule into a requirement.

The Swift tests use the toolchain-supplied Testing module when available. This
allows new coverage alongside the existing Swift 5.10-compatible XCTest suite,
as supported by [Apple's Swift Testing guidance](https://developer.apple.com/xcode/swift-testing/).
No production Swift implementation changed.

## Trials and retained tools

Keep Prettier. Separate temporary copies of 41 root-owned JavaScript,
TypeScript, JSON, CSS and HTML files were formatted with the pinned tools.
Three subsequent check runs had median elapsed times of 0.315 seconds for
Prettier and 0.150 seconds for Oxfmt. Both accepted their own output, but nine
files differed between formatters. This small local default-settings experiment
shows a possible speed benefit, not formatting equivalence or a workload-wide
performance result. It does not justify changing the repository's output now.

Keep MkDocs and nix4vscode. The [pilot results](technology-pilot-results.md)
record the exact pins and comparisons. Zensical required renderer, Markdown
extension and theme changes; successful builds initially hid broken code-block
rendering. The alternative extension catalog resolved all compared identifiers
but selected an older Oxc release. Neither migration established a sufficient
benefit for the current configuration.

Keep the 16 registered temporary fixes at the current pins. Their existing
review and applicability checks pass on all three declared platforms. That
proves the guards accept the pinned inputs, not that every patch has had a new
runtime reproduction. Two apparent removal candidates still apply: Nixpkgs
selects nh 4.4.2 without the Darwin HOME fix, and its PrismLauncher base is
11.0.3, below the selected 11.1.0 release. No guard was refreshed or patch
removed without evidence that its removal condition holds.

## Verification

- Linux Nix builds passed for `javascript-quality`, `temporary-package-fixes`
  and `python-tests`. The Python check passed 96 cases; 46 cases remain assigned
  to their existing separate generated-artifact and integration checks.
- The renderer suite passed all nine tests. Removing XML escaping in a
  disposable copy made the new test fail on malformed XML and altered entity
  text. Production code was not mutated.
- Desktop and Darwin system derivation evaluation passed with only
  `nix-command flakes` enabled in the invoking CLI. This checks evaluation;
  the running Nix daemon still uses its existing configuration.
- Native macOS debug and release runs passed 19 XCTest cases and all four
  Swift Testing tests, containing 15 parameter combinations, with Swift 6.3.3.
  The new file passed swift-format. This run did not repeat sanitizers or
  establish Swift 5.10 runtime compatibility.
- nix-seal passed 200 Linux workspace tests, Clippy with warnings denied and
  rustfmt. After independent code review added an observable runtime-absence
  assertion, all five preparation tests passed again. Cargo vet passed its
  existing policy with 15 fully audited, eight partially audited and 238
  exempted dependencies. Those exemptions remain part of the assurance limit.

The broader root hook check encountered formatting, executable-bit, Python
lint/type and workflow-permission-comment failures in other ongoing work.
The aggregate integration owner received the captured failures. The one
attributable deadnix finding in the new JavaScript check was repaired. This
report does not claim that the complete shared working tree passed all hooks.

## Website research follow-ups

The coordinated website research arrived after this implementation scope was
set. Its launch, URL policy, sitemap dates, metadata, accessibility and external
link checks remain researched follow-ups. No website implementation owner has
been assigned for those items. The aggregate integration task owns only the
Pages workflow permission comments needed by its hook check; it retains the
existing deployment behavior. The framework pilot is complete, but it does not
constitute a Pages launch or acceptance of those website changes.

## Deferred work

The user deferred the independent backup destination and live backup. No backup
was created, disk reformatted, firmware key enrolled, host activated or system
rebooted by this task. Disk migration and Secure Boot rollout retain their
verified-backup prerequisite.

The nix-seal drills use disposable generated identities. They do not replace an
independent external security audit, restoration from the owner's actual offline
recovery material, or native boot/service recovery tests. Those requirements
remain open while nix-seal is retained.
