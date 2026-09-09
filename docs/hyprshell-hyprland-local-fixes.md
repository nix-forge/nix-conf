# Local Hyprshell and Hyprland fixes

Implementation follow-up to the September 6, 2026 [patch review](hyprshell-hyprland-patch-review.md). The local changes preserve the user's asynchronous Hyprshell patch and existing Hyprland ancestry/test work. Unrelated configuration changes were preserved.

## Hyprshell

The [downstream patch](../overlays/temporary/patches/hyprshell-modifier-state.patch) targets v4.10.8, `61ddaa30563c1f091ca5fbe5d7203c19f42b519c`.

A Lua binding now captures the compositor's keyboard timestamp before spawning the independent IPC process. Escape records its GTK keyboard-event timestamp. The open handler discards older timestamped opens, including ones delivered after cancellation. Comparison handles the 32-bit timestamp wrap. The cancellation marker expires after five seconds measured with a monotonic clock, so a long-lived daemon cannot mistake a new chord for an old event after half the timestamp cycle (24.9 days). The window covers delayed local delivery across many 150 ms modifier-query deadlines; it does not cover arbitrarily delayed opens. Untagged explicit IPC commands continue to mean new requests. A legitimate new quick chord after Escape still opens and commits when its modifier has already been released.

The modifier query now distinguishes unsupported capability from transient failure. If the compositor has no query support, actual GTK or compositor modifier-release events can still commit. The GTK seat's modifier mask prevents committing when the other physical side remains held. Shift-only release bindings were removed, and the release binding ignores unrelated held modifiers. The GTK controller is retained so reconfiguration replaces it instead of accumulating handlers.

The existing atomic left/right query, asynchronous I/O, 150 ms deadline, one in-flight request, cancellation IDs, 80 ms timer while open, and warning suppression remain. A timeout or malformed response is not evidence of release.

### Compatibility limits

The local desktop uses Lua and Hyprland 0.56. Compatibility tests simulate an unsupported query using an IPC proxy on that compositor. This validates the fallback path, not a complete old-compositor runtime. Legacy bindings cannot attach the original compositor keyboard timestamp. Untagged messages cannot distinguish a delayed old open from a new explicit request, and legacy focus-handoff gaps are not fully recovered without a query. The upstream port must describe those limits honestly and test a real supported legacy compositor before claiming parity.

## Hyprland

The [production patch](../overlays/temporary/patches/hyprland-subsurface-parent-lifetime.patch) targets the pinned Nix source `ee0409623e2d6a683374b39a32e0ac3d087841aa`.

Both parent walks use a strong reference to the current ancestor and check expired surface/subsurface references. They read the current ancestor's role rather than repeatedly using the original parent. A live three-level chain accumulates offsets 10 + 20 + 30 once each and resolves the top-level surface. If ancestry disappears, position lookup retains the reachable partial offset, and top-level lookup returns null. Existing cycle rejection remains.

Preferred-color lookup checks the nullable parent and uses the existing monitor/window/compositor fallback. A stale subsurface role in `get_subsurface` produces a protocol error. The expanded rendered-orphan test also found an unchecked surface resource in `CSubsurface::size()`. That overload now delegates to the existing geometric overload, which returns the last known size after resource destruction.

The [native regression patch](../tests/hyprland/subsurface-ancestry-tests.patch) contains five hyprtester cases. It is separate because the ordinary Nix package source excludes hyprtester. Apply both patches when porting to a full upstream tree. The existing dirty upstream checkout at `~/Developer/upstream/Hyprland` was extended after snapshotting its diff, rather than reset. Its touched base files match the pinned Nix source exactly.

## Validation

The five [native integration tests](assets/hypr-patch-fixes/hyprland-native.txt) pass in an isolated headless compositor. The [standalone protocol client](assets/hypr-patch-fixes/hyprland-protocol.txt) passes all 20 runs, five each of parent-first orphan teardown, client disconnect, orphan preferred-color feedback, and child-first destruction. The existing [unit test binary](assets/hypr-patch-fixes/hyprland-unit-summary.txt) reports 422 passes. Its old coverage files produced checksum warnings; the unit suite is supplementary and does not replace the protocol tests.

The standalone runner now bounds compositor IPC and startup waits and accepts an explicit headless output. Direct nested startup hung on this graphics setup, and a headless parent alone did not supply an output. Creating a headless output, as hyprtester does, let all lifecycle tests execute. Both attempts failed before sending the protocol test requests and were cleaned up.

The [Hyprland Nix package build](assets/hypr-patch-fixes/hyprland-package.txt) succeeded. Its output is `/nix/store/y04i0kmsd4cdq4y6k9bp4kyv7g9aili8-hyprland-0.56.0+date=2026-09-04_ee04096`. This is an isolated package build, with the production patch applied to the pinned source. The compositor was not activated in the desktop session.

The [Hyprshell Nix package build](assets/hypr-patch-fixes/hyprshell-package.txt) succeeded and its [two timestamp tests](assets/hypr-patch-fixes/hyprshell-unit.txt) passed. Its output is `/nix/store/88ls7080w1y642hqj0r3lqi7zs1ydavw-hyprshell-4.10.8`. All 20 protocol cases also pass against the final [Hyprland package](assets/hypr-patch-fixes/hyprland-protocol-package.txt).

The global out-of-memory event interrupted its initial build before an output was produced. Subsequent heavy commands use `/tmp/nix-conf-heavy-work.lock`, Nix `--max-jobs 1 --cores 2`, and `CARGO_BUILD_JOBS=2`.

The final Hyprshell runtime results are:

| Check | Result |
| --- | --- |
| [Cancellation ordering](assets/hypr-patch-fixes/hyprshell-cancellation.txt) | Delayed old open rejected; next quick chord commits |
| [Unsupported query](assets/hypr-patch-fixes/hyprshell-compatibility.txt) | Ordinary release, Shift release, both Alt sides, and held Tab pass |
| [Stalled IPC](assets/hypr-patch-fixes/hyprshell-timeouts.txt) | Escape stays responsive; requests cancel, time out, and recover; warnings remain bounded |
| [Keyboard and message ordering](assets/hypr-patch-fixes/hyprshell-keyboard.txt) | 22 keyboard checks and 30 concurrent open/release pairs pass |
| [Strengthened timing checks](assets/hypr-patch-fixes/hyprshell-timing-focus.txt) | 200 fixed-seed chords select the recent window and leave no overlay |

The Nix override runs the timestamp test module during normal Hyprshell package builds, using the same check flags as the verified package. That module now contains four tests, including the cancellation-lifetime regressions described below. This release's root binary had no unit tests; the relevant tests live in `hyprshell-windows-lib`. No dependency or lockfile change was needed. Patch digests and exact derivations are saved in [artifact identities](assets/hypr-patch-fixes/artifacts.json).

The repeated test sequence is available as `tests/hyprland/check_alt_tab_package.py`. On an idle desktop with the required windows and input access, run it with the Hyprshell binary as its only argument. Run `check_alt_tab_compatibility.py BINARY cancel`, `check_alt_tab_compatibility.py BINARY legacy`, and `check_alt_tab_ipc_timeout.py BINARY` for the separate fault cases. These commands temporarily route the normal daemon socket to the test daemon and restore it afterward.

The pre-fix Hyprshell binary was `/nix/store/c46hkwgw417jsrrspk8nj1xwqdpmmxgy-hyprshell-4.10.8/bin/hyprshell`. The cancellation test failed with `Delayed cancelled open changed focus`. The unsupported-query test failed with `Unsupported query prevented modifier-release commit`. Each run restored the normal service and original focus. The proxy harness now routes compositor-spawned commands from the normal Hyprshell socket to the private test daemon; previously, physical key bindings targeted the stopped service and produced false failures. Tests that cancel or navigate an established picker also allow its keyboard focus handoff to finish before sending the next key.

The initial expanded Hyprland orphan test crashed in `CSubsurface::size()` during damage processing. The original installed two-guard package also failed the standalone orphan color-feedback/teardown scenario on its third iteration. That failure confirms an incomplete lifetime repair but does not alone attribute the crash to the color lookup, because the test also tears down the child. The native test directly checks preferred-color fallback after orphaning.

Runtime checks used the configured Alt/window mode. Ctrl, Super, workspace mode, and an actual legacy compositor remain validation requirements for the upstream port. The installed desktop compositor and normal Hyprshell service were restored; these changes have not been activated as a new desktop generation.

## Using the prompts

Use the updated [Hyprshell prompt](hyprshell-upstream-codex-prompt.md) and [Hyprland prompt](hyprland-upstream-codex-prompt.md). They ask the next session to port and revalidate the current local changes against refreshed upstream sources, preserve the tests, recheck duplicate work, and follow current contribution rules. Historical test results must not be reported as results for a new build.

Hyprland's [AI policy](https://github.com/hyprwm/.github/blob/main/policies/AI_USAGE.md) permits local code and testing but requires human understanding, review, and disclosure. The human must write and submit upstream communication; major policy violations can lead to a permanent ban. The prompt retains that boundary and the current vouch requirement. No upstream branch, PR, issue, discussion, or comment was published.

## Cancellation marker lifetime regression

Review found that retaining the last Escape timestamp indefinitely broke the signed wrapping comparison after 2³¹ milliseconds. The patch now records `Instant` alongside that timestamp and only compares events within a five-second cancellation window. Tests advance a supplied monotonic instant without sleeping: delayed older events remain rejected at the window boundary, the marker expires just beyond it, adjacent timestamp wrapping remains ordered, and a legitimate chord after half a cycle is accepted. The original helper fails both new expiry tests; the repaired helper passes all four timestamp tests. Normal Hyprshell package builds select the same `event_time_tests` module. The native package build on `desktop` passed all four tests and produced `/nix/store/pg83xvggh05ngdbrnmgi54y34wxsn45q-hyprshell-4.10.8` from `/nix/store/198vlcpv6mr11q41ngcqg1sr0q7sha24-hyprshell-4.10.8.drv`. The patch applies and reverses against its pinned source with `--fuzz=0`, and the patched Rust file passes `rustfmt --check`. No interactive desktop automation was used for this regression.
