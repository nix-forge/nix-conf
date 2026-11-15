# Hyprland desktop improvement review

## Verdict

The current desktop has the right shape. It uses UWSM, one portal stack,
PipeWire with WirePlumber, Hypridle and Hyprlock, plus one panel, launcher,
notification daemon, and OSD. Replacing that with a popular dotfiles bundle or
a monolithic shell would make it harder to diagnose and less declarative.

The best improvements are small and testable. They make UWSM own more
application lifetimes, make sleep locking explicit, and add a physical-monitor
profile without weakening the existing Sunshine profile.

## What already matches upstream guidance

* `programs.hyprland.withUWSM = true` and user services attached to
  `graphical-session.target` match Hyprland's UWSM guidance. UWSM handles the
  session environment, XDG autostart, and clean shutdown. [Hyprland systemd
  startup documentation](https://wiki.hypr.land/Useful-Utilities/Systemd-start/)
* The `hyprland;gtk` portal order, PipeWire, and WirePlumber are correct. XDPH
  supplies Hyprland capture and global-shortcut support, while the GTK backend
  supplies the file picker that XDPH deliberately does not implement. Keep
  DMA-BUF and the 120 FPS portal default for the existing high-refresh Sunshine
  use case. [XDPH documentation](https://wiki.hypr.land/Hypr-Ecosystem/xdg-desktop-portal-hyprland/)
* The existing lock, DPMS, and suspend ordering is correct: request the logind
  lock, then power down outputs, then suspend. Hypridle retains application
  idle inhibitors by default, which matters for a presentation or video.
  [Hypridle documentation](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/)
* Ironbar, Walker, SwayNC, and SwayOSD remain good choices for this GTK4-first
  desktop. Walker is already configured with a narrow default provider set,
  and SwayNC and SwayOSD each have a single service owner. [Walker
  README](https://github.com/abenz1267/walker), [Ironbar
  README](https://github.com/JakeStanger/ironbar), [SwayNC
  README](https://github.com/ErikReider/SwayNotificationCenter), [SwayOSD
  README](https://github.com/ErikReider/SwayOSD)

## Recommended implementation

### 1. Launch graphical applications through UWSM

The launcher and several Hyprland bindings currently execute graphical
applications directly. Configure Walker's `app_launch_prefix` as `uwsm app --`
and use the same prefix for long-lived graphical bindings such as Nautilus and
the terminal. UWSM specifically recommends application units rather than child
processes of the compositor. This gives applications a visible user-unit
lifetime and makes them stop with the session. Do not wrap short commands such
as `swayosd-client`, `swaync-client`, `loginctl`, `wpctl`, or `hyprctl`.
[UWSM launch guidance](https://wiki.hypr.land/Useful-Utilities/Systemd-start/)

### 2. Make the lock-before-suspend handshake explicit

Set `inhibit_sleep = 3` in the generated `hypridle.conf`. Mode 3 is Hypridle's
"lock notify" mode. It blocks sleep until the lock screen reports that the
session is locked, while leaving D-Bus, systemd, and Wayland idle inhibition at
their secure defaults. Add `immediate_render = true` to Hyprlock's `general`
section. It draws the configured Carbon Neon background immediately instead of
waiting for resources. [Hypridle general settings](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/),
[Hyprlock general settings](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/)

### 3. Add an opt-in physical-monitor profile

The active `SUNSHINE` output is deliberately a headless, fixed 2562x1656
stream. Keep it untouched. Add a separate declarative monitor profile with an
explicit connector name, mode, scale, position, and optional VRR. It should be
disabled by default until the actual monitor and GPU are tested with
`hyprctl monitors`.

For a 4K HDR monitor, make 10-bit and colour-management settings opt-in. The
Hyprland monitor documentation calls HDR experimental and warns that some
applications cannot capture a 10-bit output. A physical monitor's configured
bit depth must match the panel for portal sharing to work reliably. Start in
SDR, validate browser sharing, then trial `bitdepth = 10` and the appropriate
colour-management mode. [Hyprland monitor documentation](https://wiki.hypr.land/Configuring/Monitors/),
[Hyprland screen-sharing documentation](https://wiki.hypr.land/Useful-Utilities/Screen-Sharing/)

The profile should also make SwayOSD target the focused output on a
multi-monitor desktop. Its upstream Hyprland example derives the monitor name
from `hyprctl monitors -j`; that avoids duplicate OSDs across displays.
[SwayOSD multi-monitor example](https://github.com/ErikReider/SwayOSD#notes-on-using---monitor)

### 4. Add testable desktop contracts

Extend the existing deployment assertions and live checks rather than adding
more background daemons. Check that:

* Walker's launcher prefix contains `uwsm app --`.
* Hypridle renders `inhibit_sleep = 3` and the lock screen renders before a
  suspend request completes.
* `hyprctl monitors -j`, `systemctl --user`, and the portal services report the
  expected active profile.
* A native Wayland browser can use the GTK file picker and complete a
  PipeWire/XDPH screen share. XWayland sharing remains a compatibility path,
  not the acceptance test, because XWayland clients cannot share the full
  Wayland desktop. [Hyprland screen-sharing documentation](https://wiki.hypr.land/Useful-Utilities/Screen-Sharing/)

## Deliberately not changing

Do not add a second portal backend, a second notification daemon, a second
panel, a generic appearance editor, or an always-running custom shell. The
current single-owner model is the reason the desktop remains debuggable.

Keep `awww` for timed and animated wallpaper rotation. Keep Hyprpaper for a
static per-output profile. Hyprpaper is a fast IPC-controlled static wallpaper
utility and does not replace the rotation service. [Hyprpaper
documentation](https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/)
