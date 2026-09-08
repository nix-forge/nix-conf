# Hyprland local ancestry validation

This is a local engineering record for understanding and reviewing the code. It is not an upstream submission draft.

The isolated worktree is `/home/ianmh/Developer/upstream/Hyprland-subsurface-local-validation`, on local branch `codex/subsurface-local-validation`. A fresh fetch resolved upstream main to `34eb03bd8da01024596c367fba66485a8c9b8ca7`. The production source in the baseline build is unmodified at that revision. The added hyprtester tests run against that baseline before the production fix is applied.

The original dirty checkout and the earlier `Hyprland-subsurface-parent-lifetime` worktree were inspected and preserved. Their diffs are saved in [the evidence directory](assets/hyprland-upstream-local-20260907). The companion test patch supplied in the configuration repository was applied first. The earlier worktree's expanded tests were then reviewed and reused, including its color protocol generation in CMake. Historical downstream build results are separate from the fresh results recorded here.

## Fresh baseline evidence

The Debug baseline build completed with the three production files unchanged from `34eb03bd8da01024596c367fba66485a8c9b8ca7`. The final baseline executable has SHA-256 `e4162dc22f48125a9bc19a8333bf392b057e0a968716052a2f1b9f2861dfaca8`. The executable copy remains in the local `baseline-bin` evidence directory and is excluded from Git. The checksums and text results are retained as review evidence.

`subsurfaceAncestry` failed in a private headless compositor. For a root with Wayland resource ID 9 and three subsurfaces at offsets 10, 20, and 30, upstream returned resource ID 16 and offset `70,70`, instead of ID 9 and `60,60`. Killing that test client with resources intact then caused the isolated compositor to receive `SIGSEGV` during disconnect cleanup.

`subsurfaceParentTeardown` waited for the deepest child's frame, then destroyed the mapped intermediate parent surface. The compositor received `SIGSEGV` before the client received its command response. The saved backtrace begins at `Desktop::View::CSubsurface::size()` and continues through `recheckDamageForSubsurfaces()` and window commit processing. This fresh result independently confirms the last-known-size correction found during downstream testing.

Both runs saved their command, isolated runtime environment, compositor logs, client/test output, exit status, and crash report under `baseline-ancestry` and `baseline-parent-teardown`. Each isolation record contains a single compositor instance using a private socket and one `headless` backend output. The active desktop compositor was outside that runtime directory.

## Fresh fixed evidence

The fixed Debug build completed at the same upstream revision. Its Hyprland executable has SHA-256 `0b7173bf0ac111866330c75bb902b1759761b2d2473fe660b067c3d5e7542fbc`. All nine selected hyprtester cases reached pass: intact deep ancestry, mapped direct-parent teardown, orphan ancestry, higher-ancestor teardown, cycle rejection, child-first destruction, disconnect with resources intact, orphan preferred-color feedback, and the expired-role destruction window.

The native run's final process shutdown is not a clean result. After reporting 9/9 passes, hyprtester requests compositor exit and immediately sends `SIGKILL`; this produced a truncated Hyprland crash report in this environment. A control run that failed before creating any subsurface produced the same post-summary artifact. The runner now records any crash report as a distinct nonzero result instead of treating hyprtester's test-case status as proof of clean process shutdown. The selected cases had already destroyed their clients and checked compositor IPC before this final harness sequence.

The standalone protocol runner completed five iterations each of mapped parent-first teardown, disconnect with resources intact, orphan preferred-color feedback, and child-first destruction. It queried Hyprland after every client to prove the compositor remained responsive. It then requested orderly compositor exit and observed status 0; the runtime log ends with `Hyprland has reached the end.` The run produced no crash report. This runner does not load the test plugin and therefore provides an independent check of the protocol and view-lifetime paths.

The Debug CTest registration contained 422 unit cases; all 422 passed in 88.30 seconds. These unit cases do not instantiate the Wayland teardown path, so they are broad regression evidence rather than a substitute for the two client-driven test paths.

After review, the intact-ancestry, direct-parent teardown, orphan-ancestry, higher-ancestor teardown, and cycle-rejection cases were tightened to query `/version` after their target operation. This makes compositor responsiveness an assertion of each native case instead of relying only on the later standalone run. The updated hyprtester executable compiled successfully, `git diff --check` passed, and the changed test file passed clang-format 21.

A first runtime rerun did not reach test dispatch. The available headless Cage, Weston 16, and Sway 1.12 parents capped `xdg_wm_base` or `wl_compositor` at version 5 while this Hyprland build requested version 6. A nested run against the active Hyprland parent failed during startup while duplicating the Wayland keyboard format-table file descriptor. These were parent-compositor startup failures, not results for the updated cases.

An independent read-only review then found that `getPreferredImageDescription()` still deduced its local `parent` as a weak pointer from `m_self`. Assigning the shared result of `t1Parent()` to that variable immediately discarded the strong owner before monitor selection. The final source now locks `m_self` into a shared pointer, guards the initial role access, and retains the selected parent through the lookup. The same review found that the test client polled its null display when handling `exit` after an explicit disconnect; `exit` is now handled before display polling. The updated Debug Hyprland, Release Hyprland, test client, and hyprtester targets all compiled successfully.

The exact final tree was then rerun with a disposable Cage 0.3.1 parent whose `wlr_xdg_shell_create` version cap was changed from 5 to 6; its wlroots 0.20.2 dependency already implements and advertises newer XDG shell versions. The runner verified the exact Debug executable, a private compositor socket, and a single `HEADLESS-2` output backed by the headless backend before test dispatch. All nine selected cases passed, including all five new `/version` responsiveness assertions. The raw result is under `final-native-rerun3`. Hyprtester again produced its known post-summary shutdown crash artifact, so the evidence wrapper returned status 2 after the 9/9 pass instead of recording a clean aggregate process exit.

## Build and static checks

The full Debug build used GCC 16.2 and completed with the native tests enabled. A separate Release configuration reproduced the current CI build flags with `CFLAGS=-Werror`, `CXXFLAGS=-Werror`, and `CMAKE_DISABLE_PRECOMPILE_HEADERS=ON`; the `all` target completed successfully with `-j2`. The build log records each of the three changed production translation units and the final links.

Repository clang-format 21 passed all six changed C++ files, and `git diff --check` passed. The exact CI format script cannot be used as an aggregate result after an in-tree build because it scans generated CMake, protocol, shader, and hyprwire files. It failed on those files and on an unchanged upstream test. No unrelated file was reformatted.

The repository-wide clang-tidy configuration failed on hundreds of existing and generated header diagnostics. Re-running the same configuration through LLVM's `clang-tidy-diff` produced no diagnostics on changed lines in the five translation units present in `build/compile_commands.json`. The separately built test plugin is absent from that compilation database; it was compiled by the Debug build and checked by clang-format, but it has no clang-tidy result.

The Nix package and NixOS VM CI jobs were not repeated. The shared heavy-work lock remained occupied by concurrent configuration-repository builds and later by an idle interactive shell. The CMake CI build, native private-compositor cases, standalone protocol suite, and unit suite completed without using or activating the desktop configuration. A clean Nix package/VM run remains useful before any human submission decision.

The review artifacts are `final-production.patch`, `final-hyprtester.patch`, and `final-local.patch` in the evidence directory. `final-SHA256SUMS` records both fixed executables and all three diffs. `fixed-protocol-clean-exit` contains the strongest independent clean-shutdown evidence. `final-native-rerun3` contains the exact-final-tree 9/9 native result and the documented final-harness shutdown artifact.

## Ownership and behavior

`m_parent` and a surface role's `m_subsurface` are Hyprutils weak pointers. They describe relationships without keeping the parent or role resource alive indefinitely. `lock()` returns a shared pointer only while the object can still acquire strong owners. In particular, Hyprutils rejects a lock during destruction even while its weak pointer's `valid()` and boolean conversion can still be true. Testing the result of `lock()` matters in destroy callbacks.

Each walk keeps its current ancestor alive with `SP<CWLSurfaceResource>`. The visited list also holds strong references, preventing visited identities from disappearing and being reused during that walk. The local role lock stays alive until its position and next parent have been read. None of these references changes long-term parent ownership.

The original loops advance `surf` but read the role from the initial `m_parent`. For offsets 10, 20, and 30, the deepest child consequently accumulates 30 + 20 + 20 and stops at an intermediate subsurface. Correct traversal reads the current surface's role, yielding 60 and the actual root surface. The tests compare the root's client and Wayland resource identity, not merely whether it has a non-subsurface role.

After ancestry loss, position lookup preserves only the reachable offset sum. This is a teardown fallback, not a recovered global position. Top-level lookup returns null for a missing ancestor or expired role resource. The visited list bounds cyclic traversal; normal protocol creation must reject a descendant as the new parent with `WL_SUBCOMPOSITOR_ERROR_BAD_PARENT`.

The three `t1Parent()` call sites are synchronized surface commit, preferred image description, and subsurface creation. Synchronized commit already checks the result. Preferred-color feedback can still reach the child after its parent surface disappears, because the protocol rejects only feedback whose own surface is gone. With forced HDR disabled, unavailable ancestry must retain the existing window/monitor/compositor fallback. The fix changes no HDR preference policy.

Unmap calls `damageLastArea()`, which obtains subsurface coordinates. Damage and surface-tree processing can also call the non-const `CSubsurface::size()` after its Wayland surface resource disappears. Delegating that overload to `size(GEOMETRIC_CURRENT)` uses the existing last-known-size fallback. The test requests a root frame after removing the intermediate surface to exercise this damage processing before destroying the child's subsurface resource.

## Protocol and upstream history

The [Wayland core protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_subsurface) explicitly unmaps a subsurface when its parent surface is destroyed. It also removes the parent association when the subsurface role object is destroyed. Parent-first cleanup is a supported lifecycle; it is not inherently a client protocol error. A descendant used as a parent is an error.

[PR 15446](https://github.com/hyprwm/Hyprland/pull/15446) is prior overlapping work. Its saved diff contains the ancestor correction, weak-lock checks, and color fallback checks. Its public record attributes commit `7c09c24` to NotPppp1116 while the PR account now appears as `ghost`. The current timeline says the head repository was deleted on July 18, 2026. There are no visible reviews or technical reasons for closure. This is neither evidence of technical rejection nor permission to resubmit. The supplied downstream patch and these preexisting tests are the porting source; this record retains the earlier PR's provenance.

The refreshed search covered issue/PR text containing `subsurface`, and `parent crash`, updated since July 18, plus the corresponding discussion searches and touched-file commit history. The open subsurface results were 16144, 15435, 15737, and 15802. They concern scanout, pointer constraints, background effects, and buffered commit bits. None repairs these parent walks. Related crash reports use different paths and do not establish the same cause. Search indexing and reports with different terminology limit duplicate detection.

A submission-readiness refresh on September 6 fetched `origin/main` again. It remained at `34eb03bd8da01024596c367fba66485a8c9b8ca7`, exactly the base used for the final native run, so no rebase or repeat run was required. The four open subsurface PRs above remained open, and inspection of the overlapping files in 15435 and 15802 found no changes to `posRelativeToParent()`, `t1Parent()`, `getPreferredImageDescription()`, `get_subsurface`, or `CSubsurface::size()`.

## Local-only boundary

The current [AI policy](https://github.com/hyprwm/.github/blob/main/policies/AI_USAGE.md), [PR guidelines](https://wiki.hypr.land/Contributing-and-Debugging/PR-Guidelines/), [issue guidelines](https://wiki.hypr.land/Contributing-and-Debugging/Issue-Guidelines/), test documentation, template, repository instructions, and organization code of conduct were reread. The relevant requirements remain as described in the task. Local implementation and tests are permitted. Human review, understanding, AI disclosure, vouch eligibility, and human-written communication are required before an upstream submission. Major AI-policy violations can lead to permanent bans. The contradictory registration instruction in AGENTS does not authorize any external write in this task.

The locally authenticated GitHub account is `IanHollow`. It has no Hyprland PR history and no matching public vouch discussion in `hyprwm/.github`; public data therefore does not establish vouch eligibility. The wiki directs contributors to request a vouch in that repository's discussions before opening a PR. That request is developer-facing communication and must be made by the human.

No upstream communication or push is part of this work. The installed desktop configuration and active compositor are outside the test environment.
