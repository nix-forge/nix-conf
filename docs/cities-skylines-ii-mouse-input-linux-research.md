# Cities: Skylines II mouse input at 4K on Hyprland

Research date: 2026-09-05.

## Conclusion

This is a Hyprland 0.56 pointer-capture regression triggered by a layer-shell
surface, not an erased Cities: Skylines II binding. A controlled desktop test
now reproduces it:

1. In a fresh game session, a real uinput middle-button drag rotates the
   camera.
2. Opening and closing the Noctalia launcher creates and removes a layer-shell
   surface.
3. After refocusing the same game, the identical drag produces no camera
   movement.

That transition is unusually specific. The mouse device, game process,
resolution, key bindings, and injected event sequence stay fixed. Only a
Hyprland-managed layer surface and focus transition occur between the passing
and failing cases.

The desktop runs Hyprland 0.56.2 at commit `efb5099`. Hyprland released that
version on August 5, 2026. On August 12, upstream merged PR 15795 as commit
`1256bd1`; the PR says it fixes the two upstream XWayland mouselook reports
15565 and 15693. The patch changes the shared default fullscreen handler so
layer surfaces are never marked above a fullscreen window during this
recalculation. That shared change is used outside the scrolling layout. The
desktop uses `dwindle`, and report 15693 also reproduced on one monitor with
`dwindle`; its symptoms were a cursor escaping capture followed by no camera
response. [Hyprland 0.56.2
release](https://github.com/hyprwm/Hyprland/releases/tag/v0.56.2), [upstream PR
15795](https://github.com/hyprwm/Hyprland/pull/15795), [merged commit
1256bd1](https://github.com/hyprwm/Hyprland/commit/1256bd180e7677aadd715e59351c09fb16e48efc),
and [dwindle XWayland report
15693](https://github.com/hyprwm/Hyprland/discussions/15693)

The full PR includes substantial scrolling-layout cleanup, but its
`src/managers/fullscreen/handler/FullscreenHandler.cpp` change is in the
default handler and replaces `ls->m_aboveFullscreen = !SET` with
`ls->m_aboveFullscreen = false`. It therefore applies to this desktop even
though the scrolling-specific parts do not. The new Noctalia reproduction
matches this exact layer-surface state transition.

The game evidence independently rules out a bad binding or dead mouse device:

- The saved key bindings remain the defaults, represented by an empty override
  list. The before-and-after settings differ in display resolution, not input
  bindings.
- The latest game log reports Unity 2022.3.71f1, initializes its Input System,
  and reports a 3840x2160 window. The installed Input System assembly identifies
  version 1.14.2. `InputManager.log` pairs both `Keyboard` and `Mouse` without
  an error.
- The old run reported a 2560x1440 window. The new run reports 3840x2160. Both
  report 240 Hz and 96 DPI.
- Runtime inspection shows Hyprland 0.56.2, one 3840x2160@240.016 output at
  scale 1.5, and `force_zero_scaling = true`. XRandR sees an unscaled
  3840x2160 XWayland desktop.
- The game uses GE-Proton11-3. Its launch option bypasses the Paradox launcher
  and starts `Cities2.exe`, but does not enable Wine's native Wayland driver.

The 1.5-scale XWayland transform remains a useful secondary diagnostic, but it
is no longer the leading cause. The monitor runs at 3840x2160 and 240.016 Hz,
while scale 1.5 gives Hyprland a 2560x1440 logical area.
`xwayland.force_zero_scaling = true` presents an unscaled 3840x2160 X11 screen
to the Windows game. This can make any pointer-constraint error more visible,
but it does not explain why the same input succeeds until a layer-shell
launcher is opened.

Hyprland documents `force_zero_scaling` as forcing scale 1 on XWayland windows
and warns that applications then need their own scaling. Its monitor
documentation says monitor layout uses scaled resolution, so this output's
logical size is 3840/1.5 by 2160/1.5, or 2560x1440. [Hyprland XWayland
documentation](https://wiki.hypr.land/0.56.0/Configuring/Advanced-and-Cool/XWayland/)
and [Hyprland monitor
documentation](https://wiki.hypr.land/Configuring/Basics/Monitors/)

This scaling seam has caused related failures. A Hyprland maintainer described
`force_zero_scaling` as a workaround that makes windows `size * scale` and
then scales them down. Hyprland's own tracker has reports of pointer locations,
clickable regions, and cursor warps becoming incorrect when
`force_zero_scaling` is combined with a scaled output. The original 2023 bug
was fixed, but later reports show the same class of problem recurring on newer
versions and fractional scales. [Maintainer explanation in issue
2566](https://github.com/hyprwm/Hyprland/issues/2566#issuecomment-1603214728),
[coordinate report 4521](https://github.com/hyprwm/Hyprland/issues/4521), and
[current fractional-scale discussion
10278](https://github.com/hyprwm/Hyprland/discussions/10278)

## Recommended production fix

Use the official Hyprland flake at a revision containing `1256bd1`, then
restart the Hyprland session. The repository lock pins revision `ee04096` from
September 4, 2026, 63 commits after the fix. Set both
`programs.hyprland.package` and `programs.hyprland.portalPackage` from that
flake. Hyprland's NixOS guide requires those packages to stay in sync.
[Hyprland NixOS guide](https://wiki.hypr.land/Nix/Hyprland-on-NixOS/),
[pinned revision comparison](https://github.com/hyprwm/Hyprland/compare/1256bd180e7677aadd715e59351c09fb16e48efc...ee0409623e2d6a683374b39a32e0ac3d087841aa)

Make Hyprland's `nixpkgs` and `systems` inputs follow the repository inputs.
Leave Hyprland's internal library pins under its control because its flake
already connects Aquamarine, XDPH, and the Hyprland libraries to compatible
revisions. Hyprlock separately declares `hyprgraphics`, `hyprlang`,
`hyprutils`, and `hyprwayland-scanner`. Point those four inputs at Hyprland's
copies so the compositor and lock screen do not carry different builds of the
same C++ libraries. Hyprlock's `nixpkgs` and `systems` inputs should follow the
repository too. [Hyprland flake](https://github.com/hyprwm/Hyprland/blob/main/flake.nix),
[Hyprlock flake](https://github.com/hyprwm/hyprlock/blob/main/flake.nix)

After deployment, repeat the exact test: launch the game, verify middle-button
camera rotation, open and close the Noctalia launcher, refocus the game, and
repeat the identical drag. The fix passes only if rotation works after several
launcher and focus cycles. Also test opening a notification or OSD because the
upstream XWayland report tied the regression to layer-based notifications.
[Upstream mouselook report
15565](https://github.com/hyprwm/Hyprland/discussions/15565)

Keep an app-specific `confine_pointer` rule as defense in depth, not as the
root repair:

```lua
hl.window_rule({
  name = "cities_skylines_ii_pointer",
  match = {
    class = "^steam_app_949230$",
    fullscreen = true,
  },
  confine_pointer = true,
})
```

Confirm the class from a live game with `hyprctl clients -j` before making the
rule permanent. Hyprland's current FAQ recommends this exact rule property
when a fullscreen game does not keep the cursor captured. Scoping it to app
949230 avoids changing pointer behavior in every fullscreen application.
[Hyprland FAQ](https://wiki.hypr.land/FAQ/#my-mouse-cursor-keeps-escaping-the-game-window)
and [window-rule
reference](https://wiki.hypr.land/configuring/core/rules/window-rules/)

Do not treat confinement alone as proof of repair. Report 15693 says
`confine_pointer` did not fix the same 0.56 regression on `dwindle`. It can
prevent ordinary cursor escape, but it does not repair stale capture state
after a layer surface changes focus. The upstream backport is the necessary
first change for the reproduced failure.

## Game-only native Wayland alternative

If the upstream backport and scoped confinement rule still leave camera delta
at zero or stopping at an edge, run this game through GE-Proton's native
Wayland driver:

```text
PROTON_ENABLE_WAYLAND=1 WINEDLLOVERRIDES="version=n,b" $(echo %command% | sed -r "s/proton waitforexitandrun .*/proton waitforexitandrun/") "$STEAM_COMPAT_INSTALL_PATH/Cities2.exe"
```

The desktop has one active output, so `WAYLANDDRV_PRIMARY_MONITOR=DP-4` should
not be needed. Add it only if Wine selects the wrong output after another
monitor is connected.

This route removes the game's XWayland scaling conversion, but it should follow
the Hyprland repair. GE-Proton11-3
documents both `PROTON_ENABLE_WAYLAND` and `WAYLANDDRV_PRIMARY_MONITOR`, lists
raw mouse input as a feature, and exposes `WAYLANDDRV_RAWINPUT` only for
adjusting or disabling its unaccelerated input. Do not set
`WAYLANDDRV_RAWINPUT` for the first test. Its default is the relevant behavior.
[GE-Proton11-3 README](https://github.com/GloriousEggroll/proton-ge-custom/blob/GE-Proton11-3/README.md#environment-variable-options)

Wine's own Wayland mouselook work implements `ClipCursor` with the Wayland
pointer-constraints protocol and emits relative motion while the cursor is
hidden. That is the right mechanism for camera movement. The Wayland protocol
defines relative motion as unaffected by monitor edges and keeps relative
events flowing while an absolute pointer is locked. [Wine mouselook merge
request](https://gitlab.winehq.org/wine/wine/-/merge_requests/4593), [relative
pointer protocol](https://wayland.app/protocols/relative-pointer-unstable-v1),
and [pointer constraints
protocol](https://wayland.app/protocols/pointer-constraints-unstable-v1)

Verify that the environment flag took effect:

1. Launch the game and inspect its Hyprland client. `xwayland` must be `false`.
2. Confirm `Player.log` still reports 3840x2160 and 240 Hz.
3. Test unlimited camera rotation, edge scrolling, wheel zoom, UI clicks in all
   four corners, focus loss and return, then a clean game exit.

The tradeoff is real. GE-Proton11-3 says the Steam overlay does not work with
Wine-Wayland and Steam Input does not work properly because the overlay is
broken. Keyboard and physical mouse input are separate from that limitation,
but a Steam Controller or controller remapping workflow should stay on the
XWayland plus `confine_pointer` solution. [GE-Proton11-3 Wayland
note](https://github.com/GloriousEggroll/proton-ge-custom/blob/GE-Proton11-3/README.md#enable-hdr)

## Falsifiable diagnostic controls

Use these only if the first two repairs do not settle the result.

### Set output scale to 1 for one test

Temporarily run DP-4 at 3840x2160@240 with scale 1, leave the game on XWayland,
and retry camera movement. Restore scale 1.5 immediately afterward. If this
alone restores the mouse, it isolates the failure to the 1.5-scale XWayland
transform. It is a strong diagnostic, but not a good permanent desktop setting
because all Wayland desktop UI becomes physically smaller.

### Disable code mods for one launch

The current game installation loads several code mods and the launch option
enables a native `version` DLL override. Append `--disableModding` to the direct
`Cities2.exe` invocation for one launch. Paradox documents that switch as the
supported way to launch Cities: Skylines II with code mods disabled. If mouse
input fails identically, restore normal mod loading and stop investigating the
playset. If the clean launch works, bisect the active playset instead of
changing the compositor. The latest logs contain no mouse, camera, cursor, or
input exception, so mods are a lower-probability cause. [Paradox support
article](https://support.paradoxplaza.com/hc/en-us/articles/29256228041490-How-to-completely-disable-remove-mods)

### Remove `libextest` from the game process only

Do not disable NixOS `programs.steam.extest` as the main fix. Extest replaces
X11 XTEST calls with a virtual uinput device and was built primarily for Steam
Controller desktop behavior on Wayland. NixOS describes its Steam option as a
translation layer for X11-generated input and Steam Input. It does not provide
the relative pointer or pointer constraint used for camera movement. The live
Steam runtime contains one extest preload, not two.

If every capture fix fails, launch the game once with an empty `LD_PRELOAD`
while leaving Steam itself unchanged. A positive result would justify a
separate extest investigation. A negative result rules it out without breaking
controller behavior system-wide. [Extest upstream
README](https://github.com/Supreeeme/extest) and [NixOS Steam module
source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/steam.nix)

### Use Gamescope only as the last fallback

Gamescope can put the Windows game in its own XWayland server and present a
native Wayland window to Hyprland. Its official flags distinguish the game
resolution, `-w` and `-h`, from output resolution, `-W` and `-H`. Its
`--force-grab-cursor` switch forces relative mouse mode. A controlled 1:1 test
would therefore use 3840x2160 for both game and output, fullscreen, at 240 Hz.
Start without `--force-grab-cursor`; add it only if the pointer still reaches
an edge. If the current Wayland backend fails to grab, test `--backend sdl`
before abandoning the experiment.
[Gamescope README](https://github.com/ValveSoftware/gamescope/blob/master/README.md#examples)
and [Gamescope option
source](https://github.com/ValveSoftware/gamescope/blob/master/src/main.cpp)

Do not make Gamescope the default before testing it. Its tracker contains open
reports where camera-turning games fail to capture the cursor or receive no
mouse events even with `--force-grab-cursor`. Hyprland users have also reported
scaled Gamescope sizing and filtering errors. This path adds another
compositor, another scale decision, and another pointer constraint, so it is a
fallback. [Gamescope cursor issue
1473](https://github.com/ValveSoftware/gamescope/issues/1473), [Gamescope grab
issue 955](https://github.com/ValveSoftware/gamescope/issues/955), [current
Wayland-backend report](https://github.com/ValveSoftware/gamescope/issues/1711#issuecomment-5382229786), and
[Hyprland/Gamescope scaling report
7442](https://github.com/hyprwm/Hyprland/issues/7442)

## Acceptance checks

A completed fix should satisfy all of these in one normal Steam launch:

- Hyprland remains at 3840x2160, 240.016 Hz, scale 1.5.
- The game reports a 3840x2160 window and 240 Hz after restart.
- Camera rotation continues through multiple long mouse sweeps in every
  direction and after opening and closing menus.
- Edge scrolling, wheel zoom, middle and right mouse buttons, and UI clicks in
  all four screen corners work.
- Switching away from the game and back does not strand or warp the pointer.
- Steam sync finishes cleanly and the 4K setting survives another restart.
- If the native Wayland path is chosen, `hyprctl clients -j` reports
  `xwayland: false`. If XWayland is retained, the app-specific confinement rule
  matches only app 949230.
