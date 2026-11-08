# Fuzzing across nix-forge

Reviewed 2026-09-21. This note identifies code worth fuzzing in each active
repository and separates useful test coverage from OpenSSF Scorecard detection.

## Scorecard and tool choice

Scorecard's Fuzzing evaluator gives 10 when it finds any recognized integration
and 0 otherwise. The [evaluator](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/checks/evaluation/fuzzing.go)
does not measure coverage, corpus quality, campaign duration, or whether the
job passes. Its [detector](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/checks/raw/fuzzing.go)
recognizes `libfuzzer_sys` in Rust, `import atheris` in a prominent Python
language, and a ClusterFuzzLite integration, among other signatures. The
[public check description](https://github.com/ossf/scorecard/blob/main/docs/checks.md#fuzzing)
currently lists fewer language signatures than the detector implements.

Use [cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz/blob/bf2fc668dafda5295aa6fd01825ee67b885f0f2b/README.md)
for Rust parsers. Use [Atheris](https://github.com/google/atheris/blob/e36da74cf42b5834c4e31d7cabb58d796695d29f/README.md)
for Python code with a bounded byte input and a property that can fail.
[Hypothesis](https://github.com/HypothesisWorks/hypothesis/blob/cd434f23be1a3598085cf096e28e6738c63b29b3/hypothesis/docs/quickstart.rst)
is useful for structured properties in ordinary tests. It does not currently
satisfy Scorecard's Python signature by itself. [ClusterFuzzLite](https://google.github.io/clusterfuzzlite/)
supports Python and Rust and provides PR fuzzing, longer batch runs, corpora,
and coverage reports. It adds a container build and more CI setup than these
small Python targets need.

## CI ownership

The six Atheris workflows used to repeat Python setup, the dependency install,
campaign limits, and crash artifact handling. The shared
[`fuzz-atheris` action](https://github.com/nix-forge/ci/tree/main/actions/fuzz-atheris)
in `nix-forge/ci` now owns those steps. Each repository keeps its own target,
triggers, runner, permissions, and required check name. The framework also keeps
its Nix setup and longer per-input timeout; two targets select Python 3.14.
Keeping these jobs local avoids changing branch protection check names when the
shared implementation changes. Callers pin the action to one reviewed commit,
along with their other general shared CI references.

`nix-seal` has one Rust-specific smoke job that installs `cargo-fuzz` and invokes
its own target selector. There is no repeated Rust setup across repositories to
extract. The `.github` repository still has no useful fuzz target or campaign to
centralize.

## Repository assessment

The baseline is the OpenSSF Scorecard API result retrieved on 2026-09-21.
Targets describe project code, not dependencies that are already fuzzed
upstream.

| Repository | Baseline | Best target and property | Decision |
| --- | ---: | --- | --- |
| [nix-seal](https://api.securityscorecards.dev/projects/github.com/nix-forge/nix-seal) | 10 | Existing cargo-fuzz targets cover plan and activation documents, templates, identities, signed artifacts, and cache state. | Retain the six targets and their CI smoke run. |
| [nix-conf](https://api.securityscorecards.dev/projects/github.com/nix-forge/nix-conf) | 0 | CRX browser extension header parsing. Invalid headers must not create output; valid headers must copy exactly the payload bytes. | Add Atheris fuzzing on PRs and weekly. |
| [nixpkgs-personal](https://api.securityscorecards.dev/projects/github.com/nix-forge/nixpkgs-personal) | 0 | Apple font payload path validation. Accepted paths must remain inside the extracted root even through a symlink. | Add Atheris fuzzing and a symlink regression test. |
| [nix-homelab](https://api.securityscorecards.dev/projects/github.com/nix-forge/nix-homelab) | 0 | Integration endpoint URL policy. Malformed authorities and controls must fail closed; plain HTTP may reach loopback only. | Add Atheris fuzzing and URL regression tests. |
| [vpn-confinement](https://api.securityscorecards.dev/projects/github.com/nix-forge/vpn-confinement) | 0 | nftables JSON policy normalization. Malformed command output must not crash diagnostics; handles and set order must not affect comparison. | Add Atheris fuzzing and malformed output regression tests. |
| [ci](https://api.securityscorecards.dev/projects/github.com/nix-forge/ci) | 0 | Weighted check partitioning. Every discovered check must appear exactly once and assignment must remain deterministic. | Add Atheris fuzzing. |
| [nix-config-framework](https://api.securityscorecards.dev/projects/github.com/nix-forge/nix-config-framework) | 0 | Nix module selector discovery over generated directory trees. Exported keys must equal the independently generated model. | Run Atheris as a driver of actual Nix evaluation. |
| [.github](https://api.securityscorecards.dev/projects/github.com/nix-forge/.github) | 0 | Community docs, VEX data, and workflow templates have no repository-owned parser or runtime that consumes arbitrary bytes. | Keep schema and workflow validation. A fuzz target added only for the score would not test project behavior. |

The Python targets run for a bounded time on each PR and on a weekly schedule.
They keep the failure signal in CI, which is more useful than a static Scorecard
marker. The Nix selector campaign is slower because every input requires a Nix
evaluation; its generated trees exercise the framework's real discovery code.

## Limits

Scorecard's public API updates after GitHub observes committed changes; the
baseline does not establish the eventual score of new targets. Atheris on a
host Python installation instruments Python bytecode. These targets do not
provide native sanitizer coverage for dependencies written in C. The campaigns
are short and should retain any minimal failure as a regression test and corpus
seed. No primary source reviewed here identifies a mature dedicated
coverage-guided engine for Nix expressions or shell scripts. The `.github`
repository has no suitable project behavior to fuzz at this time.
