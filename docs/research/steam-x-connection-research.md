# Steam cannot connect after an X11 socket disappears

Reviewed: 2026-10-12. Scope: Hyprland revision e368c13, Xwayland,
systemd 261.3, Cage 0.3.1 and wlroots 0.20.2 on Linux.

## Answer

The standard X11 filesystem socket disappeared while Xwayland remained running.
The session's `DISPLAY` was correct. A direct `XOpenDisplay` call failed, matching
Steam's connection error. Hyprland's second filesystem listener survived.
Restoring the standard path as a hard link to that verified listener made
`XOpenDisplay` and `xrandr --listmonitors` pass. Steam subsequently created a
window visible in Hyprland's client list. The desktop session continued running.

The process that removed the path is unknown. This investigation establishes
the immediate failure and recovery, not the originating deletion operation.

## Findings and sources

[Steam's support article](https://help.steampowered.com/en/faqs/view/2112-4548-B98B-3A06)
explains that the client requires an X connection. Enabling Xwayland or changing
`DISPLAY` does not repair a missing endpoint when both are already correct.

[Hyprland's socket implementation at the running revision](https://github.com/hyprwm/Hyprland/blob/e368c13/src/xwayland/Server.cpp)
creates the standard filesystem socket and, with abstract sockets disabled,
a second socket with an underscore suffix. This explains the surviving
listener. The recovery changes the pathname clients use to reach that listener;
it does not bypass X server access checks.

The installed [systemd X11 tmpfiles policy](https://github.com/systemd/systemd/blob/v261.3/tmpfiles.d/x11.conf)
uses `D` entries with a one-hour cleanup age.
[NixOS reactivation](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/nixos/modules/system/boot/systemd/tmpfiles.nix)
runs tmpfiles with `--create --remove` outside boot. However,
[systemd's cleanup implementation](https://github.com/systemd/systemd/blob/v261.3/src/tmpfiles/tmpfiles.c)
protects sockets listed in `/proc/net/unix`, including in the `D` removal path.
Both listeners appeared in the inspected network namespace. The tmpfiles
services did not use a private network namespace. These observations do not
establish tmpfiles as the cause. An
[upstream namespace limitation](https://github.com/systemd/systemd/issues/42771)
shows why that protection must not be assumed across isolated namespaces.

A headless GUI probe used the same socket directory, but selected display `:1`.
[Cage assigns its selected display before spawning clients](https://github.com/cage-kiosk/cage/blob/v0.3.1/cage.c),
and [wlroots 0.20.2 preserves that display during cleanup](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/xwayland/server.c).
Removing another display's socket also changes the shared directory's timestamp.
The timestamp alone cannot identify when the desktop socket disappeared or
attribute its deletion to that probe.

The repository's [regular-file ClamAV scanner](../../modules/nixos/security/clamav_scan.py)
does not scan sockets or implement unlinking or quarantine. No evidence from
this investigation attributes the failure to that scanner.

## Recovery and prevention

Inspect the actual session `DISPLAY`, Xwayland process, filesystem socket and
`ss -xlpn` together. A listener in the socket table with no corresponding
filesystem entry indicates an unlinked endpoint. Existing connected clients
can continue working while new clients fail.

Only restore a missing path after verifying that the surviving socket belongs
to the active session, responds to the X11 handshake and has the expected
owner. Do not overwrite an existing endpoint or assume display zero. A hard
link to Hyprland's verified fallback can recover the session without restarting
the compositor. If no verified listener survives, a new desktop session is the
appropriate recovery.

Keep manual temporary-file cleanup scoped to directories owned by the task.
Do not delete live X11 socket directories or lock files. Run headless display
tests with isolated temporary storage and display allocation, preferably in a
build sandbox or VM. These practices prevent interference classes; they do not
prove which operation caused this incident. Do not disable X server access
control with `xhost +` to repair a missing socket.

If this recurs, record the unlinking process with a narrow administrator-managed
audit watch on the X11 socket directory before changing cleanup policy. Such a
watch needs administrative access and was not installed during this investigation.

## Validation and limits

The live X connection test failed before recovery and passed afterward.
`xrandr` enumerated the desktop monitor and Steam produced a window afterward.
Inspection covered generated tmpfiles rules, service journals, network namespaces,
running listeners and the relevant source implementations. A lightweight
`strace` diagnostic of Cage starting and stopping a headless display showed it
creating and removing only display `:1`; the desktop endpoint survived.
This did not reproduce the deletion. Original raw captures
remain outside the repository.

No desktop configuration change, system build or activation was necessary for
this recovery. There is no automated regression test for the unidentified
deletion operation. A permanent fix targeting that operation requires evidence
identifying its owner. The recovery was verified in the current session;
future recurrence has not been ruled out.
