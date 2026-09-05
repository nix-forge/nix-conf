# Steam HiDPI on Hyprland research

Research date: 2026-09-05.

## Conclusion

Keep Hyprland's `xwayland.force_zero_scaling = true` and render Steam's CEF
desktop UI at the matching 1.5 device scale. For the currently installed Steam
client build, the lowest-risk working bridge is a small, locally maintained and
tested CEF interposer in `nixpkgs-personal`.

This is a temporary compatibility measure. Prefer Valve's supported
`STEAM_FORCE_DESKTOPUI_SCALING=1.5` or `-forcedesktopscaling 1.5` as soon as a
future client build demonstrably honors either control again.

## System-specific evidence

The ASUS PG32UCWM is running at 3840 x 2160 with a Hyprland output scale of
1.5, yielding a 2560 x 1440 logical desktop. Hyprland explains that
`force_zero_scaling` avoids compositor resampling and pixelated XWayland text,
but requires each X11 application's toolkit to provide its own scale
([Hyprland XWayland documentation](https://wiki.hypr.land/configuring/extra/xwayland/)).

The installed Steam client build `1788400362` receives both of Valve's
documented desktop scaling controls in its launcher command and environment,
but its `steamwebhelper` processes do not receive a corresponding CEF device
scale and the desktop window remains at roughly 1x. This makes another flag
combination a weak choice for this particular build.

Local symbol inspection gives the interposer a narrow compatibility target:
the installed 64-bit `steamwebhelper` imports `cef_initialize`, while its
matching `libcef.so` exports `cef_set_force_device_scale_factor` and the
matching getter. The package tests the required post-initialization call order
against a mock CEF library.

## Options considered

### Valve's built-in scale controls

Valve added system scaling and documented both
`STEAM_FORCE_DESKTOPUI_SCALING=<float>` and
`-forcedesktopscaling <float>` in the June 2023 Steam client update
([Valve release notes](https://store.steampowered.com/news/posts/?enddate=1687195871&feed=steam_community_announcements%EF%BF%BD)).
These remain the preferred long-term solution because they avoid binary
interposition. They are not the deployed solution because both were verified
as ineffective in the installed 2026 client build. Other users have reported
client versions ignoring the same controls
([Valve issue 11200](https://github.com/ValveSoftware/steam-for-linux/issues/11200)).

`GDK_SCALE` is not a reliable substitute for Steam's CEF desktop UI; the
long-running Steam HiDPI report also records it as ineffective
([Valve issue 9585](https://github.com/ValveSoftware/steam-for-linux/issues/9585)).

### Native Wayland Steam

Native Wayland would remove this XWayland scaling tradeoff, but the feature
request remains unresolved and the Linux desktop client continues to exhibit
the XWayland blur/tiny-UI split at fractional scale
([Valve issue 4924](https://github.com/ValveSoftware/steam-for-linux/issues/4924),
[Valve HiDPI issue 7224](https://github.com/ValveSoftware/steam-for-linux/issues/7224)).
Wayland-native games also still have Steam Input, overlay, and recording
integration gaps
([Valve issue 12038](https://github.com/ValveSoftware/steam-for-linux/issues/12038)).

### Compositor scaling

Disabling `force_zero_scaling` restores the expected apparent size but asks
Hyprland to enlarge a 1x XWayland buffer by 1.5. That is the blurry and
pixelated result this work is intended to remove. It remains the safest
fallback if the CEF symbol changes after a Steam update.

### Gamescope

Gamescope is a well-maintained Valve compositor with explicit nested and output
resolution controls
([Valve gamescope](https://github.com/ValveSoftware/gamescope)). Wrapping the
entire Steam client would also introduce another compositor around launched
games, however, and is disproportionate for one UI scale problem. It also has
reported fractional-sizing behavior
([gamescope issue 1392](https://github.com/ValveSoftware/gamescope/issues/1392))
and active HDR/color-management problems affecting Steam UI
([gamescope issue 1497](https://github.com/ValveSoftware/gamescope/issues/1497)).
Those tradeoffs are especially unattractive on this NVIDIA, 4K/240 Hz, HDR
desktop.

### `steam-hidpi-shim`

The referenced project is a readable MIT-licensed implementation of the only
mechanism that matched the installed CEF binary. Its repository has two commits
from one day, no tags or releases, no CI, and no automated tests. Its preload
also applies its scale hook to any inherited process that calls CEF and exports
an unnecessary `cef_execute_process` pass-through. It is useful prior art, but
not a suitable unmodified runtime dependency for this system.

The personal package derives the essential post-`cef_initialize` call from
commit `f6651b1d6e85800885ea2b251ffc37c4e68df7e4` with attribution. It improves
the boundary by requiring an executable basename of exactly `steamwebhelper`,
requiring an explicit valid finite scale, doing nothing after failed CEF
initialization, failing open when the scale symbol disappears, exporting only
the required hook, enabling linker hardening, and testing all of those cases.

## Operational notes

The override is a 64-bit library because Steam's CEF helper is 64-bit. Steam's
32-bit bootstrap may print a harmless wrong-ELF-class preload warning before
skipping it. The package is inert in non-`steamwebhelper` executables, but its
path can still be inherited by game processes. If a game or anti-cheat rejects
any inherited preload, restore the supported Steam flags or compositor-side
scaling for that session.

After every substantive Steam client update, first retry the documented Valve
controls without this library. If the installed CEF binary removes either
symbol, Steam continues without the forced scale; remove the package rather
than chasing an undocumented replacement blindly.

## Deployment verification

The package build passed its strict compiler, behavioral, symbol-export, ELF64,
and linker-hardening checks. A full desktop build and dry activation were run
on `desktop`; the generation diff added `steam-cef-scale-override 1.0.0`,
removed `steam-hidpi-shim`, and changed no other package.

After activation, Steam was restarted with one-run debug logging. The real
64-bit `steamwebhelper` mapped the packaged library, retained both preload paths
in its environment, and logged that it applied the requested device scale. The
XWayland sign-in window measured 700 x 440, consistent with a 1.5 device scale,
and both system and user failed-unit counts remained zero.
