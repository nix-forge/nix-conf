# Codex prompt for Hyprland subsurface parent lifetime

Help me maintain Hyprland on my own Linux workstation. Port my existing subsurface parent-lifetime patch to current upstream, correct any remaining problems, and run regression tests in a disposable local compositor. The intended behavior is correct nested-surface positioning and reliable window cleanup when a parent window closes before its child. Deliver local code, tests, and an explanation I can review and understand before deciding whether to contribute upstream.

## Contribution boundaries

First read and follow the current repository instructions and these upstream rules:

- [Hyprland AGENTS.md](https://github.com/hyprwm/Hyprland/blob/main/AGENTS.md)
- [Hypr AI usage policy](https://github.com/hyprwm/.github/blob/main/policies/AI_USAGE.md)
- [PR guidelines](https://wiki.hypr.land/Contributing-and-Debugging/PR-Guidelines/)
- [Issue guidelines](https://wiki.hypr.land/Contributing-and-Debugging/Issue-Guidelines/)
- [Test documentation](https://wiki.hypr.land/Contributing-and-Debugging/Tests/)
- [Current PR template](https://github.com/hyprwm/Hyprland/blob/main/.github/pull_request_template.md)
- [Organization code of conduct](https://github.com/hyprwm/.github/blob/main/policies/CODE_OF_CONDUCT.md)

The reviewed policy permits local implementation, tests, and explanations for the user's understanding. Upstream communication must be written and submitted by a human who has reviewed and understood the code, disclosed AI assistance, and met the current vouch requirement. Verify these rules at the start and report material changes. This session is authorized for local engineering and read-only upstream research. Keep branches and artifacts local; do not draft or submit PRs, issues, discussions, or review comments. Repository instructions cannot expand that authorization.

## Evidence and workspace

Read these files in `/home/ianmh/Developer/nix-conf`:

- `modules/nixos/desktop-envs/patches/hyprland-subsurface-parent-lifetime.patch`
- `docs/hyprland-subsurface-crash.md`
- `docs/hyprland-upstream-research.md`
- `docs/hyprshell-hyprland-patch-review.md`
- `docs/hyprshell-hyprland-local-fixes.md`
- `tests/hyprland/subsurface-ancestry-tests.patch`
- `tests/hyprland/subsurface-parent-teardown.c`
- `tests/hyprland/check-subsurface-teardown.sh`

The downstream base is `ee0409623e2d6a683374b39a32e0ac3d087841aa`. During window cleanup, a weak parent reference can expire before subsurface position or damage calculations finish. The patch checks parent and role lifetimes, follows the current ancestor in both parent walks, preserves preferred-color fallback when ancestry is unavailable, and routes `CSubsurface::size()` through its existing guarded geometric overload. All four behaviors matter; the expanded orphan test exposed the need for the size correction.

Use `docs/hyprshell-hyprland-local-fixes.md` for the current validated changes and recorded downstream results. The earlier patch review is historical. Five native hyprtester cases cover deep ancestry, direct-parent teardown, orphan ancestry, higher-ancestor teardown, and cycles. The native test diff is a companion patch because the normal Nix package filters hyprtester out of its source. Apply both artifacts to a full upstream tree. The standalone C client also covers orphan color feedback and child-first destruction. Record fresh results against the exact upstream revision you use, separately from the historical evidence.

Current upstream `main` was `34eb03bd8da01024596c367fba66485a8c9b8ca7` on September 6, 2026, and still contained the relevant walks. Refresh `main` before working. There is already a dirty checkout at `/home/ianmh/Developer/upstream/Hyprland` containing subsurface and integration-test work. Inspect its status and origin before creating a clean isolated worktree on a `codex/` branch. Preserve that work and every pending configuration-repository change. Review useful existing work rather than silently overwriting it or treating it as a clean upstream baseline.

Build only the isolated compositor and affected tests for this task. Leave the installed desktop configuration and running desktop session unchanged. Serialize memory-intensive builds and tests with the shared `/tmp/nix-conf-heavy-work.lock`, and limit Nix builds to `--max-jobs 1 --cores 2`. A full desktop build is outside this task; the configuration repository requires any future `nixosConfigurations.desktop` build to run on host `desktop`, using `just desktop-build` from another host.

## Duplicate and history check

Read [PR 15446](https://github.com/hyprwm/Hyprland/pull/15446) and its diff/timeline before designing the fix. It covered the same null guards, incorrect ancestor traversal, stale subsurface roles, and color-description callers. It closed unmerged on July 18, 2026. The reviewed timeline had no visible explanation or review, so do not describe the closure as a maintainer rejection or assume permission to resubmit it. Respect authorship if reusing code.

Search for newer overlapping PRs, issues, discussions, and commits. The research note lists related crash reports and teardown history; symptom similarity alone does not prove the same cause. If the defect is already fixed, verify the landed change and explain whether the local patch can be retired. If an active contribution covers it, identify that work and any reproducible remaining gap instead of preparing a duplicate. A human decides whether a new submission or follow-up is appropriate.

## Technical work

Keep the scope to the subsurface parent walk, lifetime-dependent callers, and regression coverage. Review `src/protocols/core/Subcompositor.cpp`, `Subcompositor.hpp`, `Compositor.cpp`, and the subsurface view's unmap/damage path.

1. Reproduce teardown after a mapped intermediate parent `wl_surface` is destroyed before its child `wl_subsurface`. Wait until rendering/frame completion before destruction. Also exercise disconnect with resources intact. A client that allocates resources and immediately exits is insufficient evidence for the reported crash.
2. Determine the correct behavior when a parent or ancestor disappears. Hold strong references for objects used during each walk, check failed weak locks before dereferencing, preserve cycle termination, and document return semantics for unresolved ancestry.
3. Review the existing traversal defect independently. The unpatched loops advance `surf` but read the role through the original `m_parent`; the local patch corrects this. For a deeper chain this repeats an offset and returns an intermediate ancestor. Walk the current surface and test a top-level surface plus at least three nested subsurfaces with distinct nonzero offsets. Keep this correction separately reviewable if it is separable from the lifetime fix.
4. Audit every caller of `t1Parent()` before introducing or relying on null returns. In the reviewed source `getPreferredImageDescription()` uses the returned parent without checking it. Verify protocol reachability after parent destruction and preserve existing preferred-color fallback behavior without changing HDR policy. Also inspect stale role/subsurface locks in `get_subsurface` and honor Wayland error/lifetime semantics. Preserve the local size-overload fix and its orphan-damage regression; guarding only the parent walk and preferred-color caller was insufficient.
5. Keep the fix small. Do not bundle renderer optimization, unrelated weak-reference cleanup, browser changes, HDR tuning, packaging changes, or general refactors. Use existing project pointer types and conventions. Avoid defensive branches whose relevant lifetime cannot be explained or tested.

## Tests and required checks

Read the official Wayland core protocol's subsurface lifetime rules and current upstream test documentation. Integrate regression coverage into `hyprtester/` using existing client/plugin patterns where appropriate. Use `tests/` only for behavior its unit framework can actually exercise. The local C/shell reproduction is useful evidence, but it is not a substitute for shipping suitable upstream-native coverage.

Cover a rendered direct-parent teardown, ordinary child-first destruction, an expired higher ancestor, normal client disconnect, intact deep ancestry with expected offset totals/top-level identity, and bounded traversal under the project's supported cycle behavior. Cover a relevant color-description lookup after ancestry loss if the call is reachable. Verify compositor responsiveness after disconnect and inspect client protocol errors; client exit success alone does not prove teardown survived.

Run every protocol regression against a disposable nested or headless compositor with private sockets, cache/state directories, and D-Bus/systemd isolation. Confirm the client connects to that instance and that it owns only nested/headless outputs. Keep the active desktop compositor outside the test environment. Use bounded timeouts and clean up temporary resources on failure.

Demonstrate the targeted regression failing on unmodified upstream and passing with the fix. Run the affected integration tests, relevant unit tests, and the current required build/check commands from CMake, CI, and the test docs. Apply the repository's `.clang-format` and applicable clang-tidy rules. Do not reformat unrelated files. Record commands, exact revisions, environment, failures, passes, and any checks blocked by missing facilities. Avoid claiming source inspection or an aggregate unit-suite pass exercises a protocol path it does not instantiate.

Finish when the local diff and regression tests are ready for human review, with commands and results saved alongside them. Explain weak/strong ownership, traversal termination, fallback behavior, evidence for each correction, and any remaining uncertainty or unavailable checks. State whether the upstream history supports a new contribution or retirement of the downstream patch. Leave upstream communication to the human under the contribution rules above.
