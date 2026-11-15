# A complete Hyprland desktop, for a real monitor

## Recommendation

Build this as a small Wayland desktop, not as a collection of unrelated
`exec-once` commands. The preferred stack is below. It is aimed at an
interactive, multi-monitor workstation that can also retain Sunshine as an
optional remote-play service.

| Job | Recommended program | Why this is the default | Do not run alongside |
| --- | --- | --- | --- |
| Session lifecycle | [UWSM](https://github.com/Vladimir-csp/uwsm) | Places the compositor, autostart applications, and background services in systemd user-session units with clean shutdown semantics. | A second session manager or a pile of duplicate compositor autostarts. |
| Compositor and compatibility | [Hyprland](https://wiki.hypr.land/) plus XWayland only where needed | Native Wayland is the normal path. Keep XWayland for games and legacy apps, then remove it only after testing the real workload. | Another compositor in the same login session. |
| Desktop portals and sharing | [xdg-desktop-portal-hyprland](https://wiki.hypr.land/Hypr-Ecosystem/xdg-desktop-portal-hyprland/) plus [xdg-desktop-portal-gtk](https://github.com/flatpak/xdg-desktop-portal-gtk) | Hyprland owns capture and global-shortcut portals. GTK supplies the file chooser that XDPH deliberately does not implement. | A catch-all portal backend or a Home Manager duplicate of the NixOS portal service. |
| Audio and video transport | [PipeWire](https://docs.pipewire.org/) plus [WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/) | PipeWire carries low-latency audio and portal video streams. WirePlumber supplies the policy that selects devices and links nodes. | PipeWire Media Session or PulseAudio as a second session manager. |
| Panel | [Waybar](https://github.com/Alexays/Waybar) | Mature, declarative, CSS-styled bar with first-party Hyprland, WirePlumber, network, Bluetooth, power, tray, and multi-output modules. It is the sensible performance and maintenance choice. | Another tray host. |
| Application launcher | [Fuzzel](https://codeberg.org/dnkl/fuzzel) | Wayland-native, deliberately small, fast, and excellent for a keyboard-driven launcher. | A second desktop-entry launcher binding. |
| Notifications and control centre | [SwayNotificationCenter](https://github.com/ErikReider/SwayNotificationCenter) | One daemon gives notifications, history, do-not-disturb, media art, a keyboard-accessible panel, and configurable quick toggles. It works on wlroots layer-shell compositors, including Hyprland. | Mako, Dunst, or any other notification daemon. |
| Volume, brightness, Caps Lock, media OSD | [SwayOSD](https://github.com/ErikReider/SwayOSD) with `brightnessctl`, `wpctl`, and `playerctl` | A focused OSD server and client. It has Hyprland monitor selection examples and handles audio and backlight devices without turning the panel into a shell. | A notification-daemon OSD script, unless deliberately replacing SwayOSD. |
| Lock and idle policy | [Hyprlock](https://github.com/hyprwm/hyprlock) plus [Hypridle](https://github.com/hyprwm/hypridle) | The pair uses the session-lock and idle protocols. Hyprlock is GPU-accelerated and uses PAM. Hypridle understands logind lock, unlock, suspend, and inhibit events. | `swaylock`, `swayidle`, or a second lock trigger. |
| Privilege prompt | [hyprpolkitagent](https://github.com/hyprwm/hyprpolkitagent), or retain a tested `polkit-gnome` agent | A graphical session needs exactly one Polkit agent for UDisks, firmware tools, and NetworkManager. Hyprpolkitagent is the native option. The existing GNOME agent is a reasonable compatibility choice if it is already reliable. | Any second Polkit authentication agent. |
| Clipboard | [`wl-clipboard`](https://github.com/bugaevc/wl-clipboard) plus [cliphist](https://github.com/sentriz/cliphist) | `wl-copy` and `wl-paste` are the basic Wayland interface. Cliphist adds a searchable text and image history. | A persistent clipboard store without a privacy policy. |
| Screenshots and annotation | [grim](https://github.com/emersion/grim), [slurp](https://github.com/emersion/slurp), and [Satty](https://github.com/gabm/Satty) | This is a simple, composable path: choose an area, capture it, then annotate it. | A global screenshot daemon unless its workflow needs one. |
| Recording and streaming UI | [OBS Studio](https://github.com/obsproject/obs-studio) through the portal | OBS is the full editor and streaming front end. The portal asks the user to choose what is shared and transports frames through PipeWire. | A direct-capture recorder for normal meetings. |
| File manager and removable media | [Thunar](https://docs.xfce.org/xfce/thunar/start) plus GVfs, Tumbler, and UDisks2 | A quick traditional file manager. GVfs supplies remote-volume integration, Tumbler thumbnails, and UDisks2 gives Polkit-mediated removable-media operations. | An automounter that silently mounts every inserted drive. |
| Terminal | [Ghostty](https://ghostty.org/docs) for a rich GPU terminal, or [foot](https://codeberg.org/dnkl/foot) when minimal resource use matters most | Ghostty is the better daily interactive terminal. Foot remains an unusually lean Wayland-native alternative, with server mode. | Multiple terminals as competing defaults. |
| Browser | [Firefox](https://wiki.mozilla.org/Platform/Wayland) or a Chromium-family browser in native Wayland mode | Use a mainstream browser with a native Wayland path, portal file chooser, and PipeWire sharing. Test conferencing and password storage after every major browser update. | Forced X11 mode except for a genuine compatibility problem. |
| Network UI | [NetworkManager](https://networkmanager.dev/docs/) plus `nm-applet` or a Waybar and SwayNC front end | NetworkManager owns connection profiles and exposes D-Bus and Polkit-mediated operations. Use `nmcli` and `nmtui` as reliable fallbacks. | `systemd-networkd` or a separate Wi-Fi manager owning the same physical links. |
| Bluetooth UI | [BlueZ](https://bluez.readthedocs.io/) plus [Blueman](https://github.com/blueman-project/blueman) | BlueZ owns the adapter and Blueman supplies pairing and device management. Let PipeWire and WirePlumber own Bluetooth audio routing. | A second Bluetooth manager or permanent pairable mode. |
| Secrets | [GNOME Keyring](https://gitlab.gnome.org/GNOME/gnome-keyring) and [libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/) | It provides the standard Secret Service API used by many desktop applications. PAM can unlock it on an authenticated login. | An unencrypted keyring created only to support autologin. |
| Theme, icons, fonts, cursor | [Stylix](https://nix-community.github.io/stylix/), Fontconfig, `noto-fonts`, `nerd-fonts`, and the existing Bibata Hyprcursor/XCursor package | Keep one declarative palette and font policy. Make the cursor available in both Hyprcursor and XCursor formats for native and XWayland clients. | Per-application theme daemons and contradictory GTK/Qt settings. |
| Power and displays | `power-profiles-daemon`, `upower`, `brightnessctl`, and `ddcutil` | Laptop backlights use `brightnessctl`. External monitors need DDC/CI through `ddcutil`, which is a separate hardware capability and should be tested per display. | TLP and power-profiles-daemon acting on the same power policy. |
| Wallpaper and night light | [Hyprpaper](https://github.com/hyprwm/hyprpaper) and [Hyprsunset](https://github.com/hyprwm/hyprsunset) | Hyprpaper supports per-output wallpaper placement and Hyprsunset applies a native colour-temperature filter. They address the parts of a local monitor experience that a headless stream does not need. | A second wallpaper manager or colour-temperature service. |
| Optional remote play | [Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/) | Keep it isolated from the ordinary local desktop. It has a different trust boundary: remote input and capture need narrow firewall, pairing, and application policy. | Treating Sunshine as the normal desktop screen-sharing implementation. |

There are better-looking all-in-one shells, especially QML-based ones, but I
would not start there. A full shell is pleasant only after it has become a
small software project with its own update and debugging cost. Waybar,
SwayNC, and SwayOSD keep presentation separate from the compositor and work
well with Nix's declarative configuration.

## What a desktop actually needs

A monitor turns the existing remote session into an ordinary desktop. The
following checklist is the useful definition of "feature complete". It also
shows what should be owned by one component rather than improvised with shell
fragments.

| Area | Required behaviour | Recommended owner |
| --- | --- | --- |
| Login and recovery | A display manager starts one user session. Logout terminates its graphical programs. Failed user services can be inspected with `systemctl --user`. | greetd or another display manager, UWSM, systemd user services |
| Outputs and input | Per-monitor scale, refresh rate, VRR policy, fractional-scaling tests, lid and hotplug handling, keyboard layouts, pointer acceleration, touchpad gestures, and an on-screen way to discover keybindings. | Hyprland, `hyprctl`, `wev`, `libinput` |
| Desktop conventions | Desktop entries, MIME defaults, `xdg-open`, XDG user directories, URL handlers, file chooser, and tray support. | xdg-utils, xdg-user-dirs, portals, Waybar tray |
| Capture and consent | Browser and meeting-app capture selects a screen or window, shows a visible user choice, and works on both a physical monitor and Sunshine's headless output. | XDPH, GTK portal, PipeWire, WirePlumber |
| Everyday controls | A panel shows workspace, focused window, clock, audio, microphone state, network, Bluetooth, battery, power profile, tray, and privacy/capture state. | Waybar |
| Interaction | Launcher, terminal, file manager, clipboard, screenshot, recording, notifications, OSD, media controls, and a logout, lock, suspend menu. | Fuzzel, Ghostty, Thunar, Cliphist, Grim, OBS, SwayNC, SwayOSD |
| Authentication | Lock before display power-off or suspend. Password prompts show in the graphical session. Password changes keep the login keyring usable. | Hypridle, Hyprlock, PAM, one Polkit agent, GNOME Keyring |
| Devices and data | Wired, Wi-Fi, VPN, Bluetooth, audio devices, printers if needed, removable and encrypted storage, camera and microphone permissions. | NetworkManager, BlueZ/Blueman, PipeWire/WirePlumber, UDisks2/GVfs |
| Appearance and accessibility | Consistent GTK and Qt appearance, fonts, cursor scaling, dark/light preference, icon fallback, input method, screen reader and magnifier if needed. | Stylix, GTK settings, qt6ct or KDE settings only if Qt applications need it, IBus/Fcitx5 when needed |
| Power and health | Idle inhibit while presenting, lock then DPMS off, suspend and resume, laptop battery, external-display brightness, temperature and disk warnings. | Hypridle/logind, power-profiles-daemon, UPower, ddcutil, Waybar |
| Security and privacy | Portal consent, non-persistent pairing, bounded Polkit permissions, encrypted secrets, clipboard retention rules, screen lock, a narrow remote-play firewall, and updates. | Portals, BlueZ, Polkit, PAM, GNOME Keyring, system firewall |

## The important boundaries

The choice of programs matters less than keeping their responsibilities clear.
These are the failure modes that make a Hyprland desktop feel flaky.

### Portal, PipeWire, and browser sharing

`xdg-desktop-portal` is the consent boundary for sandboxed applications. It
offers selective access to files, URIs, screenshots, screencasts, remote
desktop input, and other resources. The upstream portal project describes
RemoteDesktop sessions as a user-controlled desktop session and pairs them
with ScreenCast's PipeWire remote. See the
[RemoteDesktop interface](https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.portal.RemoteDesktop.xml)
and [Flatpak's desktop-integration documentation](https://docs.flatpak.org/en/latest/desktop-integration.html#portals).

For Hyprland, install the Hyprland portal and the GTK fallback. XDPH's own
documentation says that it has no file picker and recommends
`xdg-desktop-portal-gtk`. It also documents a `max_fps` setting, defaulting to
120, and explains that DMA-BUF is faster than SHM while SHM can work around
some multi-GPU failures. That makes DMA-BUF the first choice for the physical
display and a diagnostic fallback, not a permanent performance setting.
[XDPH documentation](https://wiki.hypr.land/Hypr-Ecosystem/xdg-desktop-portal-hyprland/)

Select portal backends once, in explicit order: `hyprland;gtk`. Do not install
several generic capture backends and hope D-Bus chooses correctly. Duplicate
portal definitions produce slow launches, missing file pickers, or capture
failures that look like application bugs.

Run PipeWire with WirePlumber. PipeWire's documentation assigns the session
manager the job of deciding which devices to open and which nodes to link. Its
permission model also relies on session-manager policy for the detailed
decision. [PipeWire session-manager documentation](https://docs.pipewire.org/page_session_manager.html)

### Session, autostart, and environment

Use UWSM for the physical and Sunshine sessions. It creates systemd units for
Wayland sessions, binds graphical-session lifetime to the login session,
handles XDG autostart, and puts graphical applications in slices that it stops
cleanly. Its README lists Hyprland as a supported compositor.
[UWSM upstream README](https://github.com/Vladimir-csp/uwsm)

Start long-running desktop pieces as user services wanted by
`graphical-session.target`: Waybar, SwayNC, SwayOSD, Hypridle, exactly one
Polkit agent, and any status applet. Use normal `.desktop` entries or UWSM
application launching for graphical applications. Reserve Hyprland keybind
commands for short commands such as volume changes and launching Fuzzel. This
avoids a common problem where an `exec-once` copy and a systemd service both
start the same daemon.

### Locking, idle, sleep, and keyrings

Hyprlock is a real lock screen rather than a cosmetic overlay. It uses the
`ext-session-lock` protocol and PAM, has fractional-scale support, and supports
native fingerprint authentication through libfprint's D-Bus interface.
[Hyprlock README](https://github.com/hyprwm/hyprlock)

Hypridle uses the idle protocol and supports logind D-Bus lock, unlock, and
before-sleep commands, as well as D-Bus inhibit requests from applications.
Use it to lock first, then turn off outputs, then suspend. Do not turn off
displays before the lock request has taken effect.
[Hypridle README](https://github.com/hyprwm/hypridle)

GNOME Keyring and libsecret are useful in a standalone compositor because
libsecret talks to the desktop-neutral Secret Service over D-Bus. It is not a
security boundary against another process running as the same user. GNOME's
security FAQ says exactly that an application running with the user's
privileges can read unlocked keyrings. Keep a password-authenticated PAM flow,
full-disk encryption, and a locked screen. Never solve autologin keyring
prompts by creating an empty-password keyring.
[libsecret project documentation](https://gnome.pages.gitlab.gnome.org/libsecret/)
and [GNOME Keyring security FAQ](https://wiki.gnome.org/Projects/GnomeKeyring/SecurityFAQ)

### Polkit, network, Bluetooth, and removable media

Polkit grants authority for privileged D-Bus operations. One agent is enough.
The current `polkit-gnome` service in this repository is fine for the first
interactive version because it has already been deliberately scoped to the
graphical session. Switch to hyprpolkitagent only after testing UDisks,
NetworkManager, and firmware prompts. Do not enable `pkexec` merely to make a
GUI prompt appear.

For a roaming or VPN-heavy machine, enable the existing NetworkManager baseline
and use it as the sole owner of physical links. Its own module correctly avoids
sharing Wi-Fi ownership with networkd. Expose state in Waybar and make SwayNC
toggles call `nmcli`; use `nm-applet` if a full connection editor is desired.
This is much less brittle than parsing command output in a custom widget.

The existing Bluetooth policy is already stronger than most desktop defaults:
not permanently pairable, pairing timeouts, privacy addresses, confirmation on
Just Works repair, and secure connections where devices support them. Keep
Blueman as the pairing UI. Audio routing remains PipeWire and WirePlumber's
job.

The existing UDisks2, GVfs, and Tumbler baseline is right for a desktop.
UDisks2 gives a user-visible mount operation a Polkit path; GVfs provides
volume and remote-filesystem integration; Tumbler creates thumbnails on demand.
Leave automatic mounting off for removable media. It is friendlier to security
and avoids surprise execution paths from a newly inserted device.

### Clipboard and screenshots

Clipboard history is convenient and quietly sensitive. Cliphist persists what
you copy, including images, one-time codes, private snippets, and sometimes
passwords from poorly behaved apps. Set a finite item limit, offer a clear or
wipe binding, run `cliphist wipe` in the lock path if that trade-off suits the
desktop, and use a password manager's autotype rather than copying passwords
where possible. A password copied by hand should not survive a lock by default.

For still captures, bind `slurp` to select and `grim` to capture. Hand the
image to Satty only when annotation is needed. For recording and livestreaming,
use OBS through the portal because it preserves the screen or window picker and
does not silently grant a process whole-desktop capture. Direct wlr capture
tools remain useful for a deliberate local recording workflow, but they are a
different trust model.

Avoid compositor capture plugins as a default, especially experimental ones.
They execute in the compositor's process and turn a simple recording feature
into code that shares Hyprland's full authority. A portal client or a separate
recorder process is the safer default.

### Panel, notifications, OSD, and monitor UX

Waybar's official feature list includes Hyprland workspaces and focused window
modules plus network, Bluetooth, PulseAudio, WirePlumber, tray, power profile,
battery, UPower, and per-output configuration. Use a boring first layout:
workspaces and focused window on the left, clock and media in the centre,
hardware and session controls on the right. Avoid high-frequency polling
scripts. Prefer native modules and event-driven signals.
[Waybar upstream README](https://github.com/Alexays/Waybar)

SwayNC is the feature-rich notification choice. Upstream documents history,
grouping, keyboard navigation, images, inline replies, do-not-disturb,
inhibition, CSS, and a control centre. Its README also warns that it is tested
with Adwaita rather than arbitrary GTK3 themes. Treat its own CSS as the
authoritative visual layer, then wire it into the shared palette rather than
forcing a third-party GTK theme over it.
[SwayNC upstream README](https://github.com/ErikReider/SwayNotificationCenter)

SwayOSD is separate on purpose. Its upstream examples show Hyprland-focused
monitor selection and commands for PipeWire output volume, brightnessctl
backlight brightness, Caps Lock, keyboard backlight, and player controls.
For an external monitor, keep `ddcutil` as a separate brightness binding and
send the result to a custom SwayOSD progress display if desired.
[SwayOSD upstream README](https://github.com/ErikReider/SwayOSD)

### Comfort and accessibility

Use Hyprpaper only after the display profile is stable. Its upstream project
supports per-monitor paths, placement modes, fractional scaling, and IPC, which
makes it a good fit for a docked laptop or a mismatched multi-monitor desk.
Hyprsunset is Hyprland's native colour-temperature service. It requires a
recent Hyprland compositor colour-transform protocol, so test it against the
pinned compositor before relying on it for a schedule.
[Hyprpaper upstream README](https://github.com/hyprwm/hyprpaper) and
[Hyprsunset upstream README](https://github.com/hyprwm/hyprsunset)

Keyboard navigation is not optional because a desktop becomes unusable when a
pointer, touchpad, or touchscreen is unavailable. Give every shell function a
keybinding, keep a visible keybinding reference, use readable base font sizes,
and check focus order in Fuzzel and SwayNC. Add Fcitx5 or IBus only when an
input method is needed. A screen reader or magnifier also needs a deliberate
integration test, not merely a package declaration.

## Alternatives that are actually worth considering

| Default | Alternative | Choose it when | Cost |
| --- | --- | --- | --- |
| Waybar | [Quickshell](https://quickshell.org/) | You want a deeply custom, animated QML shell and are willing to own QML code. | More code, more moving pieces, and a larger runtime. |
| Fuzzel | [rofi-wayland](https://github.com/lbonn/rofi) | You need its wide collection of modes, scripts, or existing Rofi workflows. | More configuration and a less focused Wayland-native design. |
| SwayNC | [Mako](https://github.com/emersion/mako) | You want a very small notification daemon and do not need history or a control centre. | Add a separate control centre or accept less functionality. |
| SwayOSD | Custom Waybar and `notify-send` scripts | The OSD needs are genuinely tiny. | Duplicated styling and less predictable hardware-key feedback. |
| Thunar | [GNOME Files](https://gitlab.gnome.org/GNOME/nautilus) | You prefer a modern GTK file manager and accept more GNOME dependencies. | Heavier than Thunar. |
| Ghostty | [foot](https://codeberg.org/dnkl/foot) | Lowest dependency and memory footprint matter more than feature breadth. | Fewer rich terminal features and a plainer UI. |
| GNOME Keyring | [KeePassXC](https://keepassxc.org/) for personal passwords | You want an explicit, separately locked password vault. | It does not replace Secret Service integration for every desktop application. |
| Sunshine | [wayvnc](https://github.com/any1/wayvnc) | A trusted LAN needs simple VNC rather than GameStream-style low-latency streaming. | Different client and security model. |

## Recommended rollout for this repository

The repository already has a strong head start. It already declares Hyprland
with UWSM, PipeWire and WirePlumber, `hyprland;gtk` portals, Fuzzel, Hyprlock
with GNOME Keyring PAM integration, UDisks2/GVfs/Tumbler, BlueZ/Blueman, a
single Polkit agent, and a narrow Sunshine setup. Those are the difficult
pieces. Do not replace them as part of a visual-desktop pass.

Add the interactive layer in this order:

1. Add Hypridle, Waybar, SwayNC, SwayOSD, `wl-clipboard`, Cliphist, Grim,
   Slurp, Satty, `playerctl`, `brightnessctl`, and a terminal and file manager
   choice. Start each daemon through the UWSM graphical session.
2. Make a physical-display profile. Test native monitor output, fractional
   scaling, cursor scaling, multi-monitor workspace routing, DPMS, external
   monitor brightness, audio-device switching, and lock-resume before styling.
3. Test portals using Firefox and one Chromium-family application: portal file
   chooser, Wayland screen sharing with audio, permission cancellation, and
   sharing on each monitor. Inspect `systemctl --user` logs before changing
   portal packages.
4. Add the Waybar modules and SwayNC control-centre toggles. Each toggle should
   invoke its authoritative service through `wpctl`, `nmcli`, `bluetoothctl`,
   or `powerprofilesctl`, rather than mutate state through a widget-local
   script.
5. Add a lock-safe clipboard policy, then test the entire sleep path: idle,
   lock, display off, suspend, wake, unlock, keyring use, Bluetooth audio, and
   external-display reconnection.
6. Keep Sunshine optional. Verify that it does not start a duplicate panel,
   locker, portal, or Polkit agent in a remote session. Recheck its firewall,
   pairing, allowed applications, and AppArmor profile after desktop changes.

## Validation checklist

Before calling the local desktop complete, verify these user-visible paths:

- Login starts one Hyprland session. Logout leaves no orphaned Waybar,
  notification, portal, or Polkit process.
- Each monitor has the correct scale, cursor size, bar, workspace behaviour,
  lock screen, screen-share picker, and OSD placement.
- File-open dialogs, browser downloads, `xdg-open`, and MIME defaults work for
  native packages, Flatpaks if used, and XWayland applications.
- Firefox and a Chromium-family browser can share a selected monitor or window
  with audio. Cancelling the picker shares nothing.
- Notifications arrive once. The control centre opens by keyboard. Do-not-
  disturb and screen-sharing inhibition behave as expected.
- Audio source and sink changes appear in the panel. Hardware keys alter the
  chosen target and show one OSD. Bluetooth disconnect cannot spill private
  audio to speakers without an intentional policy decision.
- Locking works from a keybinding, idle timeout, and pre-suspend action. The
  screen only powers down after the lock is active.
- A removable unencrypted device requires a conscious mount action. An
  encrypted device follows the expected Polkit and passphrase path.
- Network and Bluetooth pairing prompts have one graphical agent. Untrusted
  devices cannot pair while the adapter is simply powered on.
- Clipboard history does not survive the security boundary chosen for the
  desktop. Screenshot and recording files land in a known private directory.
- Sunshine works only when explicitly enabled and does not weaken local monitor
  behaviour.

## Sources and scope

This note uses upstream projects, standards, and official documentation rather
than rices or distro how-tos. It was researched on 2026-08-26. Versions should
be checked against the pinned Nix inputs before implementation because Wayland
and portal compatibility moves quickly.

The sources that establish the underlying interfaces are the
[XDG Desktop Portal documentation](https://flatpak.github.io/xdg-desktop-portal/),
[RemoteDesktop D-Bus definition](https://github.com/flatpak/xdg-desktop-portal/blob/main/data/org.freedesktop.portal.RemoteDesktop.xml),
[PipeWire documentation](https://docs.pipewire.org/),
[Hyprland documentation](https://wiki.hypr.land/), and
[UWSM upstream documentation](https://github.com/Vladimir-csp/uwsm).
The program-specific links in the tables point to each project's own source or
documentation.

## Implementation addendum: current module interfaces

This section was checked against this flake's locked Nixpkgs revision
`4382ed2b7a6839d4280a9b386db49cbc5907414d` and its locked Home Manager
source on 2026-08-26. It is deliberately about module boundaries. It is not a
copy-and-paste desktop configuration.

Put user-session programs and UI in Home Manager. Keep kernel drivers,
hardware access, D-Bus services, PAM, and portals in NixOS. A module that only
adds packages and Hyprland binds stays usable with Sway, Niri, or another
Wayland compositor. A Hyprland-specific module may depend on
`wayland.windowManager.hyprland` and its IPC, but must not start a second copy
of a session daemon.

| Area | Current interface | Recommended boundary and notes |
| --- | --- | --- |
| Bar | Home Manager `programs.waybar.enable`, `settings`, `style`, and `systemd.enable` | Make this a generic Wayland bar module. Set `systemd.enable = true` and leave its targets at `config.wayland.systemd.target`, which makes it follow UWSM. Use Waybar's native Hyprland, audio, network, Bluetooth, power, tray, and clock modules. Do not run it through Hyprland `exec-once`. |
| Launcher | Home Manager `programs.fuzzel.enable` and `settings` | This is already correctly host-local in `homes/desktop/local/launcher.nix`. Keep application launching generic. Keep Hyprland bindings in a separate integration module. Run `fuzzel --check-config` in a Home Manager activation check or a manual smoke test. |
| Notifications | Home Manager `services.swaync.enable`, `settings`, and `style` | This module owns the D-Bus notification name and starts a user service at the Wayland session target. Enable exactly one notification daemon. Do not enable SwayNC's notification-triggered `exec` rules in a default module. Use a static, reviewed configuration only. |
| OSD | Home Manager `services.swayosd.enable`, `topMargin`, and `stylePath` | The module starts `swayosd-server`; binds call `swayosd-client`. Keep its privileged libinput backend disabled. Hyprland media and brightness bindings are enough. Backlight access is hardware policy, not UI policy. |
| Idle and lock | Home Manager `services.hypridle.enable`, `settings`, and `systemdTarget`; existing `programs.hyprlock` | Have Hypridle target `config.wayland.systemd.target` and start only there. Use `loginctl lock-session` plus an idempotent Hyprlock command before DPMS or sleep. Keep both `ignore_dbus_inhibit` and `ignore_systemd_inhibit` false, or video calls and games will be interrupted. The existing NixOS Hyprlock module already supplies PAM and enables the system Hypridle service, so choose one owner before adding the Home Manager service. For this repository, use Home Manager for the generated Hypridle configuration and explicitly disable the NixOS `services.hypridle` owner, or retain NixOS and generate only a config file. Never enable both. |
| Clipboard | Home Manager `services.cliphist.enable`, `clipboardPackage`, `allowImages`, `extraOptions`, and `systemdTargets`; `wl-clipboard` comes from `clipboardPackage` | Make history opt-in. Use bounded `extraOptions`, for example `-max-items` and `-max-dedupe-search`; disable images by default on a work machine. The HM service launches the single supported `wl-paste --watch` watcher. Bind explicit view, copy, and `cliphist wipe` actions. Do not claim that a clipboard manager can reliably identify secrets. |
| Screenshots | `pkgs.grim`, `pkgs.slurp`, `pkgs.satty`, and `pkgs.wl-clipboard` in `home.packages` | This is a reusable package-and-command module, not a daemon. Keep the generic command overridable. Its Hyprland integration can bind `grim -g "$(slurp)" -t ppm - | satty --filename - ...`; PPM avoids PNG compression before annotation. Put output under an XDG pictures or screenshots directory with mode `0700`. |
| Recording and sharing | NixOS `xdg.portal.enable`, `extraPortals`, `config`, and `xdgOpenUsePortal`; NixOS `programs.obs-studio.enable`, `plugins`, and `enableVirtualCamera` | The repository already has the right portal order: Hyprland then GTK. Do not add a Home Manager portal stack. OBS must use the ScreenCast portal and PipeWire. Only enable `programs.obs-studio.enableVirtualCamera` when the virtual camera is wanted: it installs `v4l2loopback` and turns on Polkit. |
| Files and removable media | NixOS `programs.thunar.enable` with optional `plugins`; `services.gvfs.enable`; `services.udisks2.enable` | These system services belong together. GVfs enables FUSE, D-Bus activation, MTP support, and UDisks2; Thunar enables Xfconf. Keep automount a deliberate user decision. Do not put remote-location credentials in Nix. |
| Wallpaper | Home Manager `services.hyprpaper.enable`, `settings`, and `systemdTarget` | Gate this module on Hyprland. It owns the service and restarts on config changes. Use one image per output, avoid preloading a pile of high-resolution files, and set `ipc = false` if dynamic switching is not needed. A non-Hyprland desktop should inject a generic wallpaper command instead. |
| Night light | Home Manager `services.hyprsunset.enable`, `settings`, and `systemdTarget` | This is Hyprland-only. Use `settings`, not the deprecated `transitions` option. It does not affect captures, which is desirable for colour-accurate screen sharing but means it cannot substitute for hardware display adjustment. |
| Laptop power | NixOS `services.upower.enable` and `services.power-profiles-daemon.enable` | Enable only where the hardware exposes them. NixOS rejects `power-profiles-daemon` with TLP or auto-cpufreq. Set an intentional UPower critical action; do not opt into risky suspend or ignore actions merely to silence an assertion. |
| Brightness and external displays | `pkgs.brightnessctl` and `pkgs.ddcutil` in the host package set | NixOS has no `hardware.brightnessctl` module anymore. Current brightnessctl does not need its old udev rules. There is also no NixOS ddcutil module. Test DDC/CI per monitor, then create a narrowly scoped user service or wrapper only if it works. `services.ddccontrol` is a different tool and driver stack, not a substitute for ddcutil. |

### Safe composition rules

1. Use `config.wayland.systemd.target` for portable Home Manager Wayland
   services. UWSM makes the graphical target available for Hyprland. Do not
   hard-code `hyprland-session.target` in components intended to stand alone.
2. A module must own either a process or its configuration, never both when an
   existing NixOS module owns the process. The present portal coordination
   module follows this rule and should remain the pattern.
3. Prefer package-derived absolute command paths in systemd services and
   user-visible bindings. Keep external text out of shell interpolation. For
   Waybar custom modules, set `escape = true` for untrusted output and use
   signal or event updates before polling.
4. Keep physical output names, EDID-dependent modes, backlight device names,
   DDC buses, and thermal paths in a host-local physical-display profile. They
   are not portable defaults. The current shared Waybar module must not be
   reused as-is: it declares itself "mostly broken" and embeds one host's
   Bluetooth MAC address, `amdgpu_bl0`, and a fixed hwmon path.
5. Build the UI modules with Linux guards. A Home Manager module intended for
   this repository's macOS profile should be a no-op unless
   `pkgs.stdenv.hostPlatform.isLinux`; every module above is Linux-specific.

### Source notes

Home Manager owns the modules for
[Waybar](https://github.com/nix-community/home-manager/blob/master/modules/programs/waybar.nix),
[Fuzzel](https://github.com/nix-community/home-manager/blob/master/modules/programs/fuzzel.nix),
[SwayNC](https://github.com/nix-community/home-manager/blob/master/modules/services/swaync.nix),
[SwayOSD](https://github.com/nix-community/home-manager/blob/master/modules/services/swayosd.nix),
[Cliphist](https://github.com/nix-community/home-manager/blob/master/modules/services/cliphist.nix),
[Hypridle](https://github.com/nix-community/home-manager/blob/master/modules/services/hypridle.nix),
[Hyprpaper](https://github.com/nix-community/home-manager/blob/master/modules/services/hyprpaper.nix),
and [Hyprsunset](https://github.com/nix-community/home-manager/blob/master/modules/services/hyprsunset.nix).
NixOS owns the relevant
[Hyprland and portal integration](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/wayland/hyprland.nix),
[OBS integration](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/obs-studio.nix),
[GVfs](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/desktops/gvfs.nix),
[Thunar](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/thunar.nix),
[UDisks2](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/hardware/udisks2.nix),
and [power profiles](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/hardware/power-profiles-daemon.nix).

The behaviour and limitations above come from the upstream
[Waybar manual](https://github.com/Alexays/Waybar),
[SwayNC](https://github.com/ErikReider/SwayNotificationCenter),
[SwayOSD](https://github.com/ErikReider/SwayOSD),
[Hypridle](https://github.com/hyprwm/hypridle),
[Hyprpaper](https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/),
[Hyprsunset](https://wiki.hypr.land/Hypr-Ecosystem/hyprsunset/),
[wl-clipboard](https://github.com/bugaevc/wl-clipboard),
[Cliphist](https://github.com/sentriz/cliphist),
[Satty](https://github.com/Satty-org/Satty),
and the [XDG ScreenCast portal specification](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html).
