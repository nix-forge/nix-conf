# Research question

Reviewed: 2026-09-13. Scope: `nix-output-monitor` 2.2.0 graph ingestion when
used as `nom --json` by `nh` 4.4.2.

## Answer

There is no released fix newer than 2.2.0 in the examined upstream or Nixpkgs
history. There is, however, a directly relevant *unmerged* upstream patch:
[PR 304](https://github.com/maralorn/nix-output-monitor/pull/304), commit
[`9dea4dfa633698dc736acc0b262946eafd801d8c`](https://github.com/maralorn/nix-output-monitor/commit/9dea4dfa633698dc736acc0b262946eafd801d8c).
It changes dependency-graph root tracking from a sequence with linear deletion
to a set with logarithmic deletion. The PR author reports that its supplied
synthetic reproduction changes from quadratic to approximately linear and that
the original large-plan case reaches its first build sooner. A local replay of
the same synthetic pattern with 16,000 planned derivations took 9,988 ms with
2.2.0 and 1,050 ms with the patch. This verifies the changed code path and
supports a guarded backport. It does not prove that the unavailable original
desktop plan has no second bottleneck.

Keep the `--no-nom` fallback for full automated desktop builds until this patch
is merged and released, or until a captured desktop plan also passes. Other
`nh` commands can use the guarded backport.

## Findings and sources

- The installed 2.2.0 corresponds to upstream tag
  [`v2.2.0`](https://github.com/maralorn/nix-output-monitor/tree/v2.2.0), whose
  target is commit
  [`bdfce803e3f6ae7e1ec0665094ddfa8e551fb27e`](https://github.com/maralorn/nix-output-monitor/commit/bdfce803e3f6ae7e1ec0665094ddfa8e551fb27e).
  Nixpkgs updated the package from 2.1.8 to 2.2.0 in
  [commit `6887e079fa57c80ff0fe0c8c8fc33a95c30bff48`](https://github.com/NixOS/nixpkgs/commit/6887e079fa57c80ff0fe0c8c8fc33a95c30bff48).
  The later Nixpkgs change to its package wrapper only makes generated-package
  overrides easier; it does not update the source version
  ([`6d27518c88e9dfecc2a0474f42627f88c7170b3e`](https://github.com/NixOS/nixpkgs/commit/6d27518c88e9dfecc2a0474f42627f88c7170b3e)).

- Upstream issue [#303](https://github.com/maralorn/nix-output-monitor/issues/303)
  identifies graph ingestion time proportional to graph edges times roots,
  supplies a portable generator and JSON replay, and records 32,000 synthetic
  derivations taking about 41 seconds with the affected version. This is source
  evidence for an algorithmic ingestion problem consistent with Nix blocking on
  a full pipe while `nom` consumes CPU. The supplied report is not evidence that
  every apparent stall has that cause.

- Open [PR 304](https://github.com/maralorn/nix-output-monitor/pull/304) is
  explicitly proposed to fix #303. Its patch changes `forestRoots` from
  `Seq DerivationId` to `DerivationSet`, replaces `Seq.filter` dependency
  removal with `CSet.delete`, and moves sorting to rendering. The author reports
  that the issue's original workload improves from 57 minutes 17 seconds to 11
  minutes 53 seconds, and reports synthetic timings that scale approximately
  linearly. This is an upstream benchmark claim, not an independently reproduced
  local result. The PR also documents a possible rendering-CPU regression when
  many roots are repeatedly redrawn without graph changes.

- The upstream main branch contains changes after 2.2.0, but its merged
  post-release changes are progress-bar and documentation work, not PR 304;
  see [the main-branch comparison from
  `v2.2.0`](https://github.com/maralorn/nix-output-monitor/compare/v2.2.0...main).
  PR 304 is still open, so neither upstream main nor a released version contains
  its root-set change as reviewed on this date.

- The local symptom is an observation, not an upstream claim: during a large
  JSON build plan, Nix waited in a pipe write while `nom --json` used CPU for an
  extended time, and bypassing `nom` allowed the build to continue. It is
  consistent with #303's ingest-bound behavior, but no trace establishes the
  exact hot function or proves that PR 304 resolves this particular plan.

## Validation and limits

This review examined the upstream tag, the post-tag main-branch comparison,
issue #303, PR 304 and its patch, plus the Nixpkgs package-history commits
linked above. The upstream PR's synthetic plan shape was replayed locally with
16,000 planned derivations. Both programs exited successfully. The stock 2.2.0
binary took 9,988 ms and the patched binary took 1,050 ms on x86_64 Linux. The
patched package built successfully, and the rebuilt `nh` wrapper directly
references that package in its store dependencies.

The focused temporary-fix lifecycle expression passed. The aggregate
`just temporary-fixes-check` did not run because an unrelated untracked file in
the `nix-homelab` input prevents Nix from constructing the current dirty flake.
The full desktop build reached the same unrelated input error before evaluating
the system closure. No index changes were made to work around that condition.
The original desktop JSON stream was not retained, so it could not be replayed.

The release conclusion is limited to the upstream refs and Nixpkgs history
reviewed on 2026-09-13. A later merge, release, Nixpkgs update, or successful
representative replay would change the decision.

## Implication for this repository

The repository carries PR 304 as a temporary patch with a Nixpkgs revision and
package-version guard. The selected `nh` wrapper receives the patched monitor
explicitly. The full desktop build recipe still passes `--no-nom`, which avoids
risk from the open PR and from any second issue that the synthetic replay does
not cover. Retire the patch when Nixpkgs packages an upstream release containing
PR 304, after rerunning the replay against the unmodified package.
