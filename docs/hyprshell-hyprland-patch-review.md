# Hyprshell and Hyprland patch review

Historical review, September 6, 2026. The subsequent local implementation is documented in [local fixes and validation](hyprshell-hyprland-local-fixes.md). That note supersedes the outstanding local findings below; retain this review for the original rationale and upstream research.

Reviewed September 6, 2026. "Hypershell" is interpreted as the installed `H3rmt/hyprshell` package.

Prepare two upstream candidates, one for each repository. The later local patches address the findings described here and still require a port and validation on refreshed upstream sources. Hyprshell targets release ordering and compatibility; Hyprland targets parent lifetime and ancestry with native integration tests. Submission depends on reproducing the defects on refreshed upstream sources and checking for newer overlapping work.

The ready-to-use implementation prompts are [Hyprshell](hyprshell-upstream-codex-prompt.md) and [Hyprland](hyprland-upstream-codex-prompt.md). These are prompts for local engineering sessions. No new Codex task or upstream contribution was created.

## Scope and evidence

The review uses the supplied patch artifacts rather than an arbitrary branch diff. Their intended behavior comes from [the Alt+Tab investigation](alt-tab-research.md) and [the compositor crash investigation](hyprland-subsurface-crash.md). Unrelated staged, unstaged, untracked, and submodule changes were excluded and preserved.

| Patch | Downstream base | Upstream checked |
| --- | --- | --- |
| `overlays/temporary/patches/hyprshell-modifier-state.patch` | v4.10.8, `61ddaa30563c1f091ca5fbe5d7203c19f42b519c` | Development branch `hyprshell`, `dce45069922d99bd702999de260f9ca19cdea957` |
| `overlays/temporary/patches/hyprland-subsurface-parent-lifetime.patch` | `ee0409623e2d6a683374b39a32e0ac3d087841aa` | `main`, `34eb03bd8da01024596c367fba66485a8c9b8ca7` |

Final reviewed patch SHA-256 values are `050d4040af9650d694c7d1f7454196471042dcd76a938bee7e8a9dd4dc28870a` for Hyprshell and `318c05ad481c73299e6cc82559c5a28169e27349a7ca13f3c2415ab6d5a5d0ec` for Hyprland.

Hyprshell changed concurrently during this review, from hash `67dd2668c33778711af0c801f9bb6958c25389c7c0aa0a29ef6b1330e678f5bc` to the final hash above. The newer version uses one asynchronous request for both modifier sides, a 150 ms timeout, request IDs, cancellation, and repeated-error suppression. Source review confirms that it addresses the original blocking-IPC and split-snapshot findings. Those are no longer outstanding findings; the implementation prompt asks the next session to preserve and test these improvements. This review did not make that patch change or validate its runtime behavior.

## Standards

One upstream submission requirement remains unmet by the patch artifacts. Hyprland requires tests for behavior its unit or integration framework can cover. The local C/shell teardown tests exist and provide useful evidence, but the patch does not carry an upstream `hyprtester` regression. Adapt those tests to the existing framework before submission. This is a coverage requirement, not a claim that the local fix has never been tested. [Current AGENTS.md](https://github.com/hyprwm/Hyprland/blob/34eb03bd8da01024596c367fba66485a8c9b8ca7/AGENTS.md), [test integration](https://github.com/hyprwm/Hyprland/blob/34eb03bd8da01024596c367fba66485a8c9b8ca7/hyprtester/CMakeLists.txt).

No other non-tool-enforced style or module-boundary violation was identified. Hyprshell keeps compositor operations in `exec-lib` and switcher behavior in `windows-lib`, consistent with its [development guide](https://github.com/H3rmt/hyprshell/blob/dce45069922d99bd702999de260f9ca19cdea957/DEVELOPMENT.md). The newer asynchronous patch also consolidates the release-state transition that was duplicated in the initial version.

Standards total: one missing upstream coverage requirement. No outstanding heuristic warrants blocking the change.

## Spec

One Hyprshell behavior gap remains visible in the final patch. This is a source-derived case, not a failure reproduced live during this review.

**P2: Delayed open can commit after cancellation.** The requirement says Escape cancels without changing focus. The [open handler](../overlays/temporary/patches/hyprshell-modifier-state.patch#L90) still treats a delayed open as a new selection after cancellation. It starts a fresh query, whose released-state result commits the selection. Request IDs reject old query responses but do not identify an old `OpenSwitch` message. Upstream could already reopen in that order; automatically committing that late open is new behavior. Define the ordering contract and test it. The concurrent test currently sends `switch:false`, then [asserts only that the overlay disappears](../tests/hyprland/check_alt_tab_release_race.py#L86). It can pass despite a focus change after cancellation.

Hyprland's two guards match the narrow documented goal of stopping a parent walk when the weak parent has expired. The existing deeper ancestry bug predates this patch and is not a failure to implement that narrow specification.

Spec total: one Hyprshell cancellation/ordering gap. Hyprland matches its narrow stated scope.

## Additional upstream readiness findings

**P1: Hyprshell's normal release now depends on successful Lua IPC.** If `repl` or `hl.is_key_down` is unavailable, `CloseSwitch(true)` only requests another query; it no longer closes through the prior event path. Query errors leave the switcher open. Both GTK and compositor modifier-release notifications use that same handler, so supported legacy configurations without the query capability cannot commit by releasing the modifier. Escape still cancels. The new repeated-error suppression fixes the original log storm but not this behavior. Detect capability and retain a defined compatible release path without treating every transient query failure as a confirmed release. This is an upstream compatibility regression; the local desktop specification explicitly uses Lua on Hyprland 0.56. [Current supported configurations](https://github.com/H3rmt/hyprshell/blob/dce45069922d99bd702999de260f9ca19cdea957/README.md#L27), [release handler](../overlays/temporary/patches/hyprshell-modifier-state.patch#L139), [error handling](../overlays/temporary/patches/hyprshell-modifier-state.patch#L123).

**Hyprland's two-line mitigation leaves another unsafe parent use.** `t1Parent()` can now return null on expired ancestry, but `getPreferredImageDescription()` immediately dereferences that result. Color-management feedback requests check the child surface's lifetime, not its parent's, before reaching this caller. An orphaned live child therefore provides a concrete candidate reproduction. The original code also had invalid-lifetime dereferences; this is an incomplete repair, not evidence that the local patch introduced the underlying crash class. Verify the path at runtime and add directly necessary fallback handling and tests. [Parent lookup](https://github.com/hyprwm/Hyprland/blob/34eb03bd8da01024596c367fba66485a8c9b8ca7/src/protocols/core/Compositor.cpp#L712), [feedback entry point](https://github.com/hyprwm/Hyprland/blob/34eb03bd8da01024596c367fba66485a8c9b8ca7/src/protocols/ColorManagement.cpp#L399).

**The existing deep-parent walk is wrong.** Both methods advance `surf` but continue fetching the role through `m_parent`. For a top-level surface followed by three subsurfaces, the deepest walk adds the immediate parent's position twice and returns an intermediate ancestor. The current local test uses only two subsurface levels with zero offsets, so it cannot detect this. Demonstrate distinct nonzero offsets and the expected top-level identity before including the correction. [Current parent walks](https://github.com/hyprwm/Hyprland/blob/34eb03bd8da01024596c367fba66485a8c9b8ca7/src/protocols/core/Subcompositor.cpp#L122).

## Upstream decisions

For Hyprshell, prepare one focused release/order fix against the development branch. [Issue 273](https://github.com/H3rmt/hyprshell/issues/273) and [issue 187](https://github.com/H3rmt/hyprshell/issues/187) document the same release-before-focus class. Their historical fix used [the plugin added in PR 287](https://github.com/H3rmt/hyprshell/pull/287), which [4.10 removed](https://github.com/H3rmt/hyprshell/blob/dce45069922d99bd702999de260f9ca19cdea957/src/util.rs#L92). Current development source still lacks the local recovery mechanisms. No current duplicate was found in the documented search. Use the canonical keysyms already delivered by [PR 471](https://github.com/H3rmt/hyprshell/pull/471), and preserve thumbnail work in the current component. Full issue, discussion, PR, rule, and search details are in [the Hyprshell research](hyprshell-upstream-research.md).

For Hyprland, prepare one focused parent-lifetime and ancestry candidate with native integration tests. [PR 15446](https://github.com/hyprwm/Hyprland/pull/15446) already proposed the same guards, traversal correction, and caller handling. It closed unmerged when its head repository was deleted, with no visible comments or review. Do not portray it as rejected on technical grounds or silently resubmit it. Current `main` still contains the defects. Keep separately demonstrable fixes in reviewable commits, preserve attribution, and leave the decision about upstream follow-up to the human. Full related records and policy sources are in [the Hyprland research](hyprland-upstream-research.md).

Hyprland permits local AI-assisted implementation and tests but requires human understanding/review and AI disclosure. It forbids AI-written PR descriptions or AI interaction with developer-facing channels and specifies permanent bans for major violations. Its current template requires a vouched contributor; the public record does not establish that `IanHollow` is vouched. The Hyprland prompt therefore ends with local code, tests, and an explanation for the user's understanding. The human must write and submit any upstream communication. [AI policy](https://github.com/hyprwm/.github/blob/73b8b146f0fd074aa4de5510f45f3ac1a24c97a3/policies/AI_USAGE.md), [PR template](https://github.com/hyprwm/Hyprland/blob/34eb03bd8da01024596c367fba66485a8c9b8ca7/.github/pull_request_template.md), [issue guidelines](https://wiki.hypr.land/Contributing-and-Debugging/Issue-Guidelines/).

## Verification and limits

This session reviewed both patches, their callers, local reproductions, current upstream source, related issues/discussions/PRs, and contribution rules. Both reviewed Hyprshell patch versions matched the existing modified v4.10.8 checkout under reverse application checks at their respective inspection times. The original patch's forward application check failed on current development because component context and the vendored crate path changed; the newer patch still uses the old crate path and requires a port. The Hyprland patch passes an application check against the inspected current-main file.

Prior notes report 22 Hyprshell keyboard checks, 200 timing cases, delayed-open and concurrent-message checks, plus Hyprland mapped teardown/disconnect checks and a desktop build. These were not rerun during this review. No compositor build, active-desktop input injection, or deployment was needed to prepare these review artifacts. New source-derived scenarios remain test requirements, not claimed runtime confirmations.

Search coverage and pagination limits are recorded in each research note. Refresh source revisions, contribution rules, and overlapping work when using the prompts. The existing dirty upstream Hyprland checkout was inspected read-only and preserved.
