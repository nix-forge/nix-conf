# Codex prompt for Hyprshell switch-mode release recovery

Port and validate the tested downstream fix in `H3rmt/hyprshell` so switch mode reliably commits when its configured modifier is released. Prepare the implementation locally for human review. Do not publish a branch, issue, comment, or PR in this session.

## Starting evidence and scope

Read these files in `~/Developer/nix-conf`:

- `modules/home/desktop/patches/hyprshell-modifier-state.patch`
- `docs/alt-tab-research.md`
- `docs/hyprshell-upstream-research.md`
- `docs/hyprshell-hyprland-patch-review.md`
- `docs/hyprshell-hyprland-local-fixes.md`
- `tests/hyprland/check_alt_tab_package.py`
- `tests/hyprland/check_alt_tab_compatibility.py`
- `tests/hyprland/check_alt_tab_ipc_timeout.py`
- `tests/hyprland/check_alt_tab_release_race.py`
- `tests/hyprland/check_alt_tab.py`
- `tests/hyprland/check_alt_tab_timing.py`

The downstream patch targets v4.10.8, commit `61ddaa30563c1f091ca5fbe5d7203c19f42b519c`. Prior desktop notes report a deterministic release-before-open failure, missed releases during the GTK focus handoff, and passing patched keyboard/timing tests. These are previous observations, not results you may claim for your build. Reproduce against your actual unmodified upstream base and record its SHA.

The September 6 local follow-up extends the user's asynchronous patch. It preserves the atomic left/right query, 150 ms timeout, request IDs, request cancellation, and repeated-error suppression. It adds capability detection and an event-based release path for unsupported queries. Generated Lua open bindings attach the original keyboard event timestamp, and Escape rejects older opens without swallowing the next quick chord. The patch also removes Shift-only release bindings and retains the GTK controller so config reload can replace it correctly. Read the local-fixes note for exact artifacts and test results. These are evidence for the downstream build, not results you may claim for a new upstream port.

Preserve the ordering contract. Timestamped Lua opens from before cancellation are stale. Untagged explicit IPC commands represent new requests. Legacy bindings cannot attach the compositor event timestamp, so this mechanism does not solve delayed-open ordering in legacy mode or every legacy focus-handoff gap. Do not claim otherwise or silently remove legacy support. Evaluate a supported legacy mechanism separately before promising equivalent recovery on old compositors.

As of September 6, 2026, the development branch is `hyprshell`, at `dce45069922d99bd702999de260f9ca19cdea957`. The default `hyprshell-release` branch is a release branch. Verify the current development target using recent accepted PRs. The patch does not apply unchanged to development: the vendored IPC crate moved to `dep-crates/hyprland`, and the switch component gained optional live thumbnails.

Use a clean isolated checkout or worktree and a `codex/` branch. Inspect existing work first. Preserve pending changes in this configuration repository and any existing upstream checkout. Do not activate system configuration or replace the running desktop daemon as part of preparing the patch.

## Upstream research and rules

Refresh applicable `AGENTS.md`, `CONTRIBUTING*`, `DEVELOPMENT.md`, README, templates, licenses, hooks, and workflows before editing. The reviewed tree had no explicit root AI policy or contribution template; recheck rather than assuming that remains true. Follow current rules and disclose assistance honestly in any locally prepared human handoff.

Read the relevant history, including comments, and search for newer overlapping work:

- [Issue 273](https://github.com/H3rmt/hyprshell/issues/273) and [issue 187](https://github.com/H3rmt/hyprshell/issues/187) describe quick modifier release before GTK receives focus.
- [PR 287](https://github.com/H3rmt/hyprshell/pull/287) introduced the historical plugin fix. Version 4.10 removed that plugin. Treat these closed reports as related history, not issues automatically closed by your work.
- [Issue 470](https://github.com/H3rmt/hyprshell/issues/470) and [PR 471](https://github.com/H3rmt/hyprshell/pull/471) already fixed canonical modifier keysyms. Reuse those helpers.
- [Issue 463](https://github.com/H3rmt/hyprshell/issues/463) concerns key events leaking to underlying applications. Preserve consumption behavior.
- [PR 519](https://github.com/H3rmt/hyprshell/pull/519) changes thumbnail cleanup in the same component. Recheck its status and conflicts.

If a complete upstream fix has landed, verify it with the relevant reproduction and explain whether the downstream patch can be retired. If an active PR already covers the work, identify the remaining gap instead of preparing a duplicate.

## Required behavior

Keep one stable recent-window snapshot during each selection. A quick chord must select the previous eligible window and leave no overlay. Repeated navigation must take effect before a later commit. Support forward/reverse entry, direction changes, the configured switch key, and window/workspace modes.

Releasing the configured modifier must commit even if Tab or Shift remains down, or if release happens before GTK acquires focus. Releasing Shift alone must not commit while the switch modifier remains held. Both physical modifier sides count: keep the switcher open until neither side is held. Check Alt, Ctrl, and Super, including overlapping left/right handoffs.

Escape must cancel without changing focus. Timers, callbacks, queued state responses, and delayed messages from a cancelled interaction must not commit a selection later. Explicitly examine delayed `OpenSwitch` after cancellation, as well as stale close messages during a new held chord. Define the ordering contract and prove it with tests. Avoid a blanket rule that drops the next legitimate quick chord.

The corrected concurrent release test sends `switch:true` and asserts both focus and overlay visibility. The 200 timing cases now also assert selection of the recent window, so a missing open cannot pass just because no overlay appeared. The separate compatibility test injects a timestamped open after Escape and checks unchanged focus, then verifies the next quick chord. Keep both assertions when porting the tests.

## Implementation constraints

Use the local patch as evidence, then implement against current source. Keep the change limited to switch-mode event/state handling, any required IPC support, and tests.

- Prefer reliable event handling, with reconciliation for the missed-event gap if needed. Keep any polling active only while a selection is open and justify its frequency.
- Preserve the newer patch's single compositor operation for both modifier sides. Two sequential requests can both return false during a handoff even when at least one side stayed pressed throughout. Verify response framing and parsing; `eval` acknowledgement is not a boolean state result.
- Keep GTK responsive. The vendor crate also has synchronous socket helpers with an unbounded `read_to_end`; keep periodic work off the UI thread. Use bounded asynchronous work or another suitably bounded design, with at most one reconciliation request in flight. Reject results belonging to an older selection or configuration.
- Preserve the README's supported Lua and legacy Hyprland configurations. Detect unsupported state-query capability, preserve working release handling, and define the recovery limits honestly. The local patch distinguishes unsupported capability from transient query errors and uses real release events with the GTK seat modifier mask as a compatibility path. Preserve and test that behavior, including both physical sides and Shift release. Unsupported or malformed responses must not themselves mean "released" and must not cause a warning every 80 ms. Use valid release-event evidence in a compatible path. Do not silently raise the minimum compositor version.
- Remove event sources on close, cancellation, reload, and component destruction. Preserve thumbnail cleanup and supported feature combinations. Do not let asynchronous completion resurrect a closed component.
- Review generated release bindings in both syntax paths. Avoid broad changes to unrelated binding semantics. Preserve explicit cancellation and document any intentional internal IPC behavior change.

Do not add styling, monitor preferences, Nix packaging changes, new configuration features, a plugin, dependency upgrades, or unrelated refactors.

## Validation and completion

Add deterministic tests around the actual state-handling code with controllable event order and state-query outcomes. Cover release-before-open, missed release, stale close while held, queued navigation before commit, both-side handoff, cancellation followed by delayed open/result, close/reopen, unsupported/malformed/timed-out queries, and timer/request cleanup. Tests must demonstrate behavior, not simply restate helper implementation.

Port or adapt the live reproductions to a disposable session with controlled windows. Assert both focus and overlay state. Exercise both modifier release orders, sustained hold, reverse switching, rapid repeated chords, all supported modifiers, and legacy/Lua paths. Restore focus and release synthetic keys on failure. If a desktop-dependent case cannot run, finish all independent implementation and tests and state the precise unverified case.

Follow the current [development guide](https://github.com/H3rmt/hyprshell/blob/hyprshell/DEVELOPMENT.md), [justfile](https://github.com/H3rmt/hyprshell/blob/hyprshell/justfile), and [CI](https://github.com/H3rmt/hyprshell/blob/hyprshell/.github/workflows/test.yml). At the reviewed revision the hook runs `just check lint test`; CI runs `cargo build`, `cargo xtask cmd check -v --locked`, `cargo xtask cmd lint -v`, and `cargo xtask cmd test -v --no-nextest --locked`. Use the current equivalent if these change. Run applicable feature coverage and formatting without adding unrelated lockfile churn.

Finish with a local reviewable diff and test evidence. Explain the mechanism, base SHA, precise failing-before/passing-after cases, compatibility behavior, remaining limits, and related upstream work. Recommend one focused PR only if the evidence still supports it. Leave publication to a separate explicit user instruction.
