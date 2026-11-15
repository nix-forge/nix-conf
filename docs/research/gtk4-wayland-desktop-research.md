# GTK4 and Wayland desktop components for Hyprland

## Recommendation

Keep the current modular desktop as the default. It already has a sensible
shape: Waybar, Fuzzel, SwayNotificationCenter, SwayOSD, Hyprlock, Hypridle,
Hyprland's portal backend, and Stylix. Do not replace all of that merely to
make every visible surface use GTK4.

The changes worth considering are additive and deliberate:

* Add Nautilus as the primary graphical file manager if a full-featured GTK4
  file experience is wanted.
* Offer Ironbar as an experimental GTK4 panel profile, while retaining Waybar
  as the stable default.
* Offer Walker or Anyrun as a richer GTK4 command palette. Keep Fuzzel as the
  fast, small default launcher.
* Keep SwayNotificationCenter and SwayOSD. Both are current GTK4 layer-shell
  components with the UI depth the desktop needs.
* Use domain-specific settings applications and a small SwayNC control center,
  not a new monolithic shell or an imperative theme editor.

## Local audit of the deployed desktop

The deployed system confirms that the visual problem is mostly configuration,
not a missing desktop shell.

* [The host Hyprland profile](../../homes/desktop/local/hyprland.nix) sets
  `gaps_in = 0`, `gaps_out = 0`, and `decoration.rounding = 0`. It therefore
  removes the spatial separation, rounded geometry, shadows, and motion that
  make a window manager feel like a modern desktop.
* The retired Waybar and SwayNC blue-grey stylesheets have been removed. The
  active Ironbar and SwayNC templates receive the Stylix palette and font
  roles through Home Manager, so a theme selection now changes their visible
  colors with the rest of the desktop.
* Current user-service health is good, but the UI needs cleanup before it
  earns the "polished" label. Waybar reports no battery on this desktop and
  WirePlumber source-node warnings; SwayNC enables a backlight widget for a
  host with no matching device. Those unavailable controls should be hidden on
  a headless profile and made host options for a physical display.
* The live services are not CPU-bound, but their resident memory is not tiny:
  Waybar reported roughly 299 MiB and SwayNC roughly 165 MiB at inspection.
  That is a reason to measure any full-shell trial against the current
  baseline, not an argument to assume a QML or JavaScript shell will be
  cheaper.

The first implementation pass should therefore keep the stable programs and
change their configuration: a Stylix-derived component palette, Inter where
text is appropriate, symbolic icons where an icon communicates faster than a
word, 10-14px layer-surface radii, and modest spacing. For Hyprland, use small
gaps, 12-14px window rounding, a restrained shadow, and short animations. The
current upstream Lua example shows supported settings for gaps, rounding,
shadow, blur, and animations. [Hyprland example configuration](https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua)

The security boundaries should remain outside the visual shell. Portals mediate
sandboxed file access and screen sharing. Polkit handles authorization. The
wallpaper service, secrets, and privileged actions should not move into a bar,
launcher, or custom widget process.

## What the repository already gets right

The current interactive desktop is already composed around one program per
job. The Home Manager desktop modules own Waybar, Fuzzel, SwayNotificationCenter,
SwayOSD, Hypridle, Hyprlock, and desktop applications. The NixOS Hyprland
module selects `hyprland;gtk` for portal backends and enables UWSM, PipeWire,
and WirePlumber. The shared Stylix module provides a single palette, Inter,
Monaspice, Papirus, and Bibata cursor policy.

That separation is good UX and good fault isolation. A launcher crash should
not take down notifications. A notification-center CSS change should not affect
the lock screen. A bar should receive only the information it displays, rather
than become the process that owns privileged system control.

Some parts are not GTK4, and that is fine:

| Area | Current choice | Assessment |
| --- | --- | --- |
| Bar | Waybar | Mature, broadly packaged, and has Hyprland modules. It uses GTK3, but its CSS is deliberately separate and Waybar supports dark and light stylesheets. [Waybar README](https://github.com/Alexays/Waybar) [Waybar configuration](https://github.com/Alexays/Waybar/blob/master/man/waybar.5.scd.in) |
| Launcher | Fuzzel | A native Wayland launcher with a very small, keyboard-first interface. No GTK4 replacement is automatically an improvement. |
| Notifications and quick controls | SwayNotificationCenter | A GTK4/libadwaita notification daemon and control center for wlroots layer-shell compositors. It has history, grouping, DND, inline replies, actions, media, calendar, audio, and backlight widgets. [SwayNotificationCenter README](https://github.com/ErikReider/SwayNotificationCenter) |
| OSD | SwayOSD | A focused GTK4 OSD for volume, mute, brightness, media, and lock state. Keep the privileged libinput watcher disabled unless explicit hardware integration needs it. [SwayOSD releases](https://github.com/ErikReider/SwayOSD/releases) |
| Lock and idle | Hyprlock and Hypridle | Hyprlock uses the ext-session-lock protocol and PAM. It is the right security-oriented choice even though it is not GTK. [Hyprlock README](https://github.com/hyprwm/hyprlock) |
| Portal and capture | xdg-desktop-portal-hyprland plus GTK backend | This is the correct pairing for a Hyprland session. The Hyprland backend owns Hyprland-specific portal work, while GTK supplies generic portal UI. [XDPH README](https://github.com/hyprwm/xdg-desktop-portal-hyprland) |

## Component choices

### Bar and panel

**Keep Waybar as the stable default.** It covers Hyprland workspaces and
windows, audio, network, Bluetooth, media, battery, tray, clock, privacy, and
custom scripts. It is a panel, not a full desktop shell. That is an advantage
for the present configuration because its scope stays easy to test and replace.
[Waybar README](https://github.com/Alexays/Waybar)

**Ironbar is the best GTK4 panel trial.** It is a Rust/GTK4 layer-shell panel
with first-class Hyprland and Sway support, rich popups, multi-monitor layouts,
hot-reloaded CSS, built-in modules, and Home Manager examples. Its asynchronous
design keeps one blocked script from freezing the rest of the panel. The
important caveat is in its own README: Ironbar calls itself alpha and expects
breaking changes. Pin the package before enabling it, keep Waybar available,
and test panels, tray, network, Bluetooth, media, and multi-monitor recovery
before considering it a default. [Ironbar README](https://github.com/JakeStanger/ironbar)

Ironbar uses GTK4 but not libadwaita. Its own styling guide says that
libadwaita-targeted themes do not apply to it. Give it a component-specific
stylesheet derived from Stylix rather than relying on global GTK overrides.
[Ironbar styling guide](https://github.com/JakeStanger/ironbar/wiki/styling-guide)

**AGS v3 is a framework, not a drop-in upgrade.** It lets a user write GTK3 or
GTK4 shell surfaces in TypeScript/JSX on GJS, Astal, and Gnim. It can make a
beautiful bespoke panel, overview, palette, or widget. It also turns desktop
configuration into executable application code and its major versions have
changed architecture. Use it only when maintaining a custom TypeScript shell
is a chosen project, not because Waybar lacks a feature. [AGS quick start](https://aylur.github.io/ags/guide/quick-start.html)

Quickshell deserves awareness as the strongest alternative for a future
single-shell experience, but it is Qt/QML rather than GTK. Choose it only if a
cohesive custom shell becomes more important than a GTK-first interface. It is
not a reason to add a second bar today. [Quickshell overview](https://quickshell.org/about/)

### Launcher and command palette

**Fuzzel remains the default.** It starts quickly, stays out of the way, and
matches a keyboard-driven Hyprland workflow. The existing configuration can
continue to use Fuzzel for simple application selection even if a richer
palette is installed separately.

**Walker is the clearest GTK4 upgrade path** when the desired change is richer
search rather than a new shell. It is a Rust/GTK4 launcher for Linux desktop
environments with sources and modules beyond desktop entries. Treat it as an
optional palette first, preserving the Fuzzel binding as a known-good fallback.
[Walker README](https://github.com/abenz1267/walker)

**Anyrun is another GTK4 option** for a plugin-driven palette. It is
Wayland-native and its upstream project provides application, shell,
calculator, dictionary, web-search, action, clipboard, and Nix-run plugins.
Use only reviewed plugins, because a launcher plugin that executes shell input
is an intentional code-execution boundary. The project's NVIDIA renderer
workaround should also be tested on the actual GPU before making it default.
[Anyrun README](https://github.com/anyrun-org/anyrun)

Rofi remains capable, but it brings historical X11-oriented behavior and
Wayland caveats. It is not the direction to choose for a fresh GTK4-focused
profile. [Rofi README](https://github.com/davatorium/rofi)

### Notifications and OSD

**Keep SwayNotificationCenter.** It is already the feature-rich GTK4 choice.
It requires a compositor with `wlr_layer_shell_unstable_v1`, which fits
Hyprland. Do not add Mako, Dunst, or another notification daemon alongside it:
there must be exactly one owner of `org.freedesktop.Notifications`. Mako is a
good low-overhead alternative for a minimal profile, but it deliberately does
not provide a control center. [SwayNotificationCenter README](https://github.com/ErikReider/SwayNotificationCenter)
[Mako README](https://github.com/emersion/mako)

SwayNC's own documentation says it is tested with default Adwaita and does not
support third-party GTK3 themes without extra work. Its schema defaults to
ignoring `GTK_THEME`. Keep the component's reviewed CSS as the visual source of
truth, avoid notification-triggered arbitrary shell rules, and do not try to
force an application-wide GTK3 theme through it. [SwayNC schema](https://github.com/ErikReider/SwayNotificationCenter/blob/main/src/configSchema.json)

**Keep SwayOSD.** Call its client from Hyprland's explicit media and brightness
bindings. The optional libinput backend observes physical key state but needs a
system service or `pkexec`; it is unnecessary for ordinary volume and
brightness shortcuts and should remain opt-in. [SwayOSD repository](https://github.com/ErikReider/SwayOSD)

### Settings and control center

There is no single GTK4 control center that is both compositor-neutral and a
better source of truth than declarative Nix configuration. Adding one tends to
make two systems fight over display, input, theme, and startup settings.

Use a small layered control surface instead:

* SwayNC handles frequently used, non-privileged controls and notification
  history.
* `iwgtk` remains the matching network UI for the existing iwd selection.
* `pwvucontrol` is already installed for PipeWire controls. Retain
  `pavucontrol` as its compatible fallback if needed.
* Blueman is the existing general Bluetooth manager. Overskride is a GTK4 and
  libadwaita option if a more modern Bluetooth-specific UI is desired, but it
  should be a trial, not a replacement for BlueZ service policy. [Overskride README](https://github.com/kaii-lb/overskride)
* GNOME Settings can be installed as an occasional launcher target if its
  individual panels are useful. Do not make GNOME Shell or its background
  services a dependency of the Hyprland session. [GNOME Settings](https://apps.gnome.org/Settings/)

Do not make `nwg-look` the appearance authority. It is a useful GTK3
compatibility editor for wlroots, but its README lists GTK3 dependencies and
its maintainer explicitly says it does not support GTK4. It also writes
GSettings directly, which conflicts with declarative Stylix values.
[nwg-look README](https://github.com/nwg-piotr/nwg-look)

`nwg-shell` remains a reasonable all-in-one GTK3 suite for people who want its
opinionated panel, drawer, dock, and configuration application. It duplicates
several components already owned by this repository, so it is not a good fit
here. [nwg-shell README](https://github.com/nwg-piotr/nwg-shell)

### File manager and related desktop applications

**Nautilus is the recommended file manager.** It is a mature GTK4 GNOME Files
application with search, local and network file management, removable-media
read/write, scripts, application launching, several views, and an extension
API. It is heavier than Thunar, but it is the better choice for a feature-rich
GTK4 desktop. Keep Thunar available only if its compact workflow is preferred.
[GNOME Files](https://apps.gnome.org/Nautilus/)

Make Nautilus the proposed `Super+E` target only after testing file chooser,
trash, archive manager, SMB/SFTP, removable media, and drag-and-drop in the
actual session. Those flows have more value than a visual toolkit label.

## Infrastructure that must not be treated as decoration

### Portals

`xdg-desktop-portal` provides D-Bus interfaces that let sandboxed applications
access files, open URIs, print, capture a screen, and request remote desktop
capabilities through the user's desktop. It is a resource-consent mechanism,
not merely a GTK file dialog. [XDG Desktop Portal overview](https://flatpak.github.io/xdg-desktop-portal/docs/)

Keep explicit `hyprland;gtk` backend precedence. Portal backend selection is
configuration-driven precisely because several desktops and backends can be
installed together. Picking the first backend found is fragile. [Portal configuration](https://flatpak.github.io/xdg-desktop-portal/docs/portals.conf.html)

Test every session change with a sandboxed file chooser, browser screen share,
PipeWire capture, URI opening, and screenshot. Verify that UWSM imports the
Wayland environment into systemd user and D-Bus activation. A visually polished
shell with unreliable portals is not a finished desktop.

### Polkit

Polkit authorizes privileged desktop operations through system D-Bus and asks a
session authentication agent when policy calls for it. It is where disk mounts,
network administration, firmware tools, and similar actions should authenticate.
[Polkit manual](https://polkit.pages.freedesktop.org/polkit/polkit.8.html)

Use exactly one authentication agent in the session. Hyprpolkitagent is the
native candidate and its upstream documentation supports starting it as a
systemd user service under UWSM. Before changing agents, test UDisks, network
changes, Bluetooth pairing, and a cancelled prompt. Never replace those flows
with a bar button that calls `sudo` or stores an administrator password.
[hyprpolkitagent documentation](https://wiki.hypr.land/Hypr-Ecosystem/hyprpolkitagent/)

## Stylix, GTK4, icons, and cursors

Stylix should remain the declarative source of shared palette, font roles,
icons, and cursors. It should not force every application to have the exact
same widget styling.

GTK4 and libadwaita are related but different. Libadwaita applications use
`AdwStyleManager` for system dark preference, accent colour, and high contrast.
Their standard widgets support dark and high-contrast styles. Overriding them
with a legacy third-party GTK theme can produce broken spacing, contrast, or
controls. Prefer the dark preference, a compatible accent, the configured
fonts, and application-local CSS only where a component owns it. [libadwaita
styles and appearance](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.3/styles-and-appearance.html)

The practical policy is:

* Keep the current Stylix dark palette and font settings. Let GTK4/libadwaita
  applications follow dark mode and high contrast in their supported way.
* Keep per-component stylesheets for Waybar, SwayNC, SwayOSD, and any future
  Ironbar profile. GTK CSS is not web CSS, so test selector behavior with each
  component's documented CSS node tree. [GTK CSS overview](https://docs.gtk.org/gtk4/css-overview.html)
* Keep Papirus as the selected icon theme, but retain Adwaita and `hicolor` as
  fallbacks. GTK's default icon theme is Adwaita and its icon loader relies on
  the standard theme plus a `hicolor` fallback. [GtkSettings icon theme](https://gnome.pages.gitlab.gnome.org/gtk/gtk4/property.Settings.gtk-icon-theme-name.html)
  [GtkIconTheme](https://gnome.pages.gitlab.gnome.org/gtk/gtk4/class.IconTheme.html)
* Keep the existing native Hyprcursor plus XCursor fallback setup. Hyprcursor
  covers clients that implement server-side cursors; GTK still needs the
  XCursor theme and size exported, with matching GSettings cursor values.
  [Hyprcursor documentation](https://wiki.hypr.land/Hypr-Ecosystem/hyprcursor/)

The Carbon Neon palette should be applied with restraint. Its teal accent can
be used for focus, selections, progress, and the primary action. Reserve error,
warning, and success roles for semantic colours. Do not turn every panel icon
and notification border teal. A readable, boring default state is what makes a
focused accent useful.

## Phased plan

### Phase 1: finish and verify the current baseline

Keep Waybar, Fuzzel, SwayNC, SwayOSD, Hyprlock, Hypridle, and explicit portal
selection. Confirm one notification daemon and one polkit agent only. Test
screen sharing, Flatpak file chooser, lock and suspend, UDisks mounting,
network changes, Bluetooth pairing, audio control, and a mixed-DPI monitor
layout. This phase changes no visual framework.

### Phase 2: add high-value GTK4 applications

Trial Nautilus as the feature-rich file manager. Trial Overskride only if
Blueman's UI is an actual pain point. Offer Walker or Anyrun as an optional
command palette without removing Fuzzel. Keep each trial behind a module option
and retain the old binding until actual desktop testing succeeds.

### Phase 3: experiment with a GTK4 panel profile

Create a separate Ironbar profile that consumes the same Stylix colours, icon
theme, font roles, media services, network stack, portal state, and wallpaper
events as the existing modules. It must not run a second notification daemon,
lock screen, portal backend, or polkit agent. Evaluate startup time, idle CPU,
memory, tray behavior, popups, monitor hot-plug, and full-screen behavior.
Promote it only if it is more pleasant and at least as reliable as Waybar.

### Phase 4: build a custom shell only for a real unmet need

Use AGS v3 if a GTK/TypeScript shell is a deliberate maintained product. Use
Quickshell if the project accepts QML and wants one integrated custom shell.
Do not build either simply to reproduce a bar, launcher, notification center,
and OSD that already work. Keep secrets, privileged actions, and source
downloaders in dedicated services whatever visual layer is selected.
