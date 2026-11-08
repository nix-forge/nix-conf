# Noctalia tray icon selection review

Reviewed: 2026-10-12; implementation validation updated 2026-10-13.
Scope: PR #4579 at
`366e0d6c7705a96be850caee4fb9402153ab7729` and upstream main at
`0c8808e8392b49385459422ce14ff28e2c2aed83`.

## Answer

All three findings are valid. Exact-path regressions reproduced the failures on
the prior integrated selector and passed after the correction. The fix preserves
the first matching theme, compares status SVG size ranges across its roots, and
keeps normal application and bitmap lookup.
[Review comment](https://github.com/noctalia-dev/noctalia/pull/4579#issuecomment-6133253771)

## Findings and sources

- Threshold directories share the parser's scalable flag. Larger sizes sort
  first, and the new selector compares distance only for non-scalable entries.
  Thus a 16px request can select 24px Threshold artwork. The specification
  distinguishes Fixed, Threshold and Scalable. Threshold covers Size plus/minus
  its tolerance; omitted Type defaults to Threshold and omitted tolerance to 2.
  Scalable uses MinSize/MaxSize, each defaulting to Size.
  [Reviewed source](https://github.com/noctalia-dev/noctalia/blob/366e0d6c7705a96be850caee4fb9402153ab7729/src/system/icon_resolver.cpp#L288),
  [metadata specification](https://specifications.freedesktop.org/icon-theme/latest/#file-formats).
- The selector stops at a different filesystem themeRoot after finding a match.
  A logical theme may span several base directories, so a better-sized asset in
  the second root is skipped. Merged PR #4607 supplies IconSearchDir::theme and
  searches all roots before inherited themes. Reuse it when updating this PR.
  [Selector](https://github.com/noctalia-dev/noctalia/blob/366e0d6c7705a96be850caee4fb9402153ab7729/src/system/icon_resolver.cpp#L540),
  [upstream fix](https://github.com/noctalia-dev/noctalia/pull/4607/files),
  [directory specification](https://specifications.freedesktop.org/icon-theme/latest/#directory-layout).
- Searching only status/panel SVGs before establishing theme ownership permits
  an inherited status icon to replace a higher-priority application icon. The
  existing symbolic-application fixture has no inherited collision. The
  specification stops inheritance when the current theme provides the name at
  any size. Context is descriptive metadata, not a separate icon namespace.
  [PR implementation and tests](https://github.com/noctalia-dev/noctalia/pull/4579/files),
  [lookup specification](https://specifications.freedesktop.org/icon-theme/latest/#icon-lookup).

## Implemented approach

The [correction](https://github.com/noctalia-dev/noctalia/commit/20749072bbd25cd58c2d405e543b7bd7754b9441)
is published on PR #4579. Current upstream was merged without rewriting
published branch history. This
incorporates #4607's theme grouping. The correction resolves normally first and
only optimizes logical size when the winner is a status/panel SVG. Eligible SVGs
are compared across every root of that winner's logical theme. Application and
bitmap winners retain normal lookup.

Explicit Fixed, Threshold and Scalable ranges determine selection distance.
Matching ranges win; otherwise the nearest range wins. Nominal design size
breaks ties, followed by stable directory/root order. The first usable
index.theme supplies metadata across the logical theme's roots. Range metadata
also participates in cache invalidation.

Regression fixtures assert exact selected paths for Threshold ranges and
defaults, split roots, inherited collisions, Scalable defaults and range-only
metadata changes. Existing precedence tests and the pinned directory-content
cache test remain intact. Logical design size and output raster density are
handled separately.

Refresh the PR's evidence with actual corrected-head results. A review response
draft is prepared; posting it requires an explicit request. Template checks do
not establish that C++ tests ran.
[Contribution requirements](https://github.com/noctalia-dev/noctalia/blob/0c8808e8392b49385459422ce14ff28e2c2aed83/CONTRIBUTING.md),
[PR checks](https://github.com/noctalia-dev/noctalia/pull/4579/checks).

## Validation and limits

Independent primary-source research and source review completed. The corrected
application built with GCC 16.2.0 and all 149 tests passed. Formatting passed with
clang-format 22.1.8, as did scoped clang-tidy.
[Upstream CI](https://github.com/noctalia-dev/noctalia/actions/runs/38411984200)
also passed its build, test, lint and formatting checks on the corrected head.
Before/after resolver probes
confirmed the regressions, including Threshold defaults, split roots, application
and bitmap precedence, Scalable defaults and size-range cache invalidation.

The pinned downstream package built successfully, including its resolver,
Hyprland workspace, bar-icon policy and route-preference checks. The broader
all-system repository evaluation was killed for memory pressure after the
package build. The subsequent native flake check and package policy, independence
and unit checks passed, including ten package test suites.

Corrected-head tray, attention state and 24px drawer captures were inspected in
a private nested Hyprland session at interface scales 1.0 and 1.5. The first
normal capture at scale 1.0 preceded bar readiness and was excluded. The
compositor rejected requested output density 1.5 and substituted another scale;
fractional-output rendering remains unverified. The fixture supplied an overlay
during attention state, which suppresses overlays; visible normal-state overlay
coverage remains unverified. Earlier harness failures produced no usable
captures. Debug builds emitted system-header `_FORTIFY_SOURCE` warnings at
`-O0`; scoped clang-tidy messages were suppressed diagnostics from disabled
checks. No desktop activation ran.

The frequency of inherited status/application collisions in installed themes
is unknown. The published Threshold-distance pseudocode has inconsistent
variables; derive distance from the defined size interval rather than copying
it literally. Context-based classification and complete theme-metadata handling
can be considered separately from these focused fixes.

## Implication for this repository

The [archived downstream tray patch](https://github.com/nix-forge/nixpkgs-personal/blob/ec5a07115e8ee49f714613a9d0cb830a192399b7/pkgs/by-name/no/noctalia-personal/tray-icon-size.patch)
at review start repeated the faulty selector atop the
[5.2.1 pin](../../pkgs/pkgs/by-name/no/noctalia-personal/source.nix).
Updating the source pin alone does not remove this implementation. The verified
correction has been ported into the owning package, preserving its local override
and advertised-name paths and its directory-content cache regression. Retire the backport when the selected
upstream release includes the fix. Desktop builds and heavy checks must use
the repository's workstation-task workflow.
