# Hyprland OLED idle display policy

Research date: 2026-09-06

Use Hypridle to turn the outputs off through DPMS while Hyprlock keeps the session locked. An animated screensaver adds rendering and leaves the panel displaying content. Display standby also permits the PG32UCWM's automatic pixel cleaning. ASUS documents prolonged static images as a burn-in risk and says cleaning runs in standby after sufficient use. Leave the monitor connected to power and retain its built-in OLED care settings. This reduces static exposure; it is not a guarantee against panel wear. [ASUS PG32UCWM product and OLED care documentation](https://rog.asus.com/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/)

## Root cause

The existing configuration in `modules/home/desktop/config/hypridle.conf.in` requested locking after 300 seconds, DPMS off after 330 seconds, and suspend after 900 seconds. Its display commands used `hyprctl eval 'hl.dpms(...)'`. Live desktop logs reported that `dpms` was a nil field, so reaching the display timeout could not turn the monitor off. The wake commands used the same invalid API.

The pinned Hyprland revision is `ee0409623e2d6a683374b39a32e0ac3d087841aa`. Its Lua API registers DPMS under `hl.dsp.dpms`. That function constructs a dispatcher closure; merely evaluating it does not execute the action. Use:

```sh
hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
```

An equivalent evaluation wraps the constructor in `hl.dispatch(...)`. The pinned source accepts `on`/`off` as aliases for `enable`/`disable`. [Pinned dispatcher implementation](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/config/lua/bindings/LuaBindingsDispatchers.cpp), [dispatcher execution](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/config/lua/bindings/LuaBindingsToplevel.cpp), [action parser](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/config/lua/bindings/LuaBindingsInternal.cpp)

## Recommended behavior

Keep the ordinary idle schedule and add a 30-second listener that only turns outputs off when Hyprlock is running. Apply `ignore_inhibit = true` to this listener so background playback cannot keep the lock screen lit. Set `condition_retry = 5` so locking after the short timeout has already elapsed still triggers display sleep. Retrying matters for the five-minute automatic lock and for locks requested remotely without new input. Hypridle 0.1.8, installed on the desktop, supports both `condition_cmd` and `condition_retry`. [Tagged configuration parser](https://github.com/hyprwm/hypridle/blob/v0.1.8/src/config/ConfigManager.cpp)

The short listener measures input idleness, not time since locking. A manual keyboard lock normally leaves about 30 seconds for the prompt. An automatic lock after five idle minutes can blank on the next condition retry. After activity wakes a still-locked session, another 30 idle seconds should blank it again. Keep `on-resume` paired with DPMS enable, and fix `after_sleep_cmd` and `on_unlock_cmd` to restore outputs too. The ordinary unlocked listeners should continue honoring playback inhibitors. These are policy choices based on Hypridle's documented listener semantics. [Hypridle configuration reference](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/)

A process check is a practical gate, not proof that the compositor has accepted the lock. Preserve `inhibit_sleep = 3` so suspend waits for the compositor lock notification. Avoid querying Hypridle's own `org.freedesktop.ScreenSaver.GetActive` method inside `condition_cmd`: the condition runs synchronously on Hypridle's event loop, which would prevent the daemon from answering its own query. Its confirmed lock state is available to `on_lock_cmd`, but adding a separate lock-state file is unnecessary for this display policy. [Hypridle 0.1.8 event loop and lock handling](https://github.com/hyprwm/hypridle/blob/v0.1.8/src/core/Hypridle.cpp)

## Verification

Completed on `desktop`:

- Reproduced the original configured wake command's nil-function error. The service journal also showed the same failure at the display-off timeout.
- Built `nixosConfigurations.desktop.config.home-manager.users.ianmh.xdg.configFile."hypr/hypridle.conf".source` and evaluated the user's Home Manager assertions, with no failed assertions.
- Executed both unique DPMS commands from the generated configuration. Batched each dispatch with a monitor query and asserted that `DP-4` reported `dpmsStatus = false` for disable and `true` for enable. Batching avoids input waking the monitor between the command and the query. Always restored DPMS on afterward.
- Checked Nix formatting and whitespace in the changed files.
- Pointed the live Hypridle configuration symlink at the newly built file and restarted the existing service while Hyprlock was absent. Hypridle loaded four listeners, including the condition and inhibitor override, and remained active with zero restarts. The rendered file has a GC root at `~/.local/state/nix/gcroots/hypridle-config`; the previous Home Manager link target is recorded beside it in `hypridle-config.previous-target`. A normal rebuild will install the same policy through Home Manager.

No full NixOS activation was needed for this configuration-only update. The password unlock and suspend/resume cycle was not exercised. Remaining interactive checks are manual lock, idle automatic lock, input wake followed by another idle period, and locking while a media inhibitor exists. The short listener's process gate should prevent display blanking during unlocked playback. An `ok` response from a Lua expression alone is insufficient evidence of DPMS behavior because constructing a dispatcher succeeds without running it.
