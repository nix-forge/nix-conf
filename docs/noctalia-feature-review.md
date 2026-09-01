# Noctalia feature review

Research date: 2026-08-27. This covers the current v5 documentation and source-owned project material only. Noctalia v5 is still beta, so treat its configuration and plugin interfaces as moving targets. [Project README](https://github.com/noctalia-dev/noctalia#noctalia) [Plugin documentation](https://docs.noctalia.dev/noctalia/plugins/)

## Decision

Use Noctalia as the only owner of the interactive shell: bar, launcher, notification daemon, OSD, clipboard history, control center, tray, media controls, session panel, and window switcher. It puts the frequently used parts of the desktop behind one visual system and one IPC command set. Noctalia is a shell around a compositor, not a replacement for Hyprland, portals, PipeWire/WirePlumber, NetworkManager, UPower, or a file manager. [Project scope](https://github.com/noctalia-dev/noctalia#scope) [IPC overview](https://docs.noctalia.dev/noctalia/ipc/)

Keep the existing Hyprlock, Hypridle, system Polkit policy, and awww-based wallpaper acquisition and rotation. They are security-sensitive or already have useful declarative behavior in this repository. Do not run their Noctalia equivalents in parallel. The Noctalia configuration should keep its wallpaper renderer, lock screen, idle actions, and Polkit agent disabled while retaining the rest of the shell.

Enable Noctalia brightness and night light after hardware validation. Leave the dock and desktop widgets off by default. They are useful on demand, but a permanent dock wastes vertical space in a tiled workflow and desktop widgets add continuous visual noise.

Avoid community plugins in the baseline. Plugin code is trusted code, even though each Luau entry uses an isolated VM and runs off the UI thread. Its runtime API includes subprocess, filesystem, HTTP, download, clipboard, and environment capabilities. Pin and review any plugin source before enabling it, and set its update policy to no automatic update in a declarative profile. [Plugin development security model](https://docs.noctalia.dev/noctalia/plugins/development/) [Plugin runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/)

## What Noctalia includes

| Area | Current capability | Baseline recommendation |
| --- | --- | --- |
| Shell surfaces | Multiple bars, a dock, launcher, Control Center, notification toasts and history, OSDs, session panel, clipboard panel, tray, lock screen, and desktop widgets. [README feature list](https://github.com/noctalia-dev/noctalia#what-it-includes) | Use all except the dock, lock screen, and desktop widgets initially. |
| Bars and widgets | Bars can sit on any edge with monitor overrides. Built-in widgets cover active window, taskbar, workspaces, clock, tray, audio, battery, Bluetooth, brightness, caffeine, clipboard, keyboard layout, lock keys, media, network, night light, notifications, power profile, privacy capture state, screenshots, session, system monitor, wallpaper, weather, custom buttons, and plugin widgets. [Bars](https://docs.noctalia.dev/noctalia/bar/) [Widget index](https://docs.noctalia.dev/noctalia/bar/widgets/) | Use a sparse top bar. Put workspaces, active window, clock, notifications, tray, Bluetooth, volume, and Control Center there. Keep high-frequency system controls in the Control Center. |
| Launcher | Application, calculator, emoji, wallpaper, session, and window providers, plus prefix-gated providers and dmenu-style custom providers. [Launcher](https://docs.noctalia.dev/noctalia/launcher/) [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/) | Use it in place of Fuzzel or Walker. Calculator may be global. Keep session, wallpaper, and window search prefix-gated so ordinary app search stays clean. |
| Control Center | Home, media, audio, monitor, system, network, Bluetooth, weather, calendar, notifications, screen-time, and power tabs. [Control Center](https://docs.noctalia.dev/noctalia/control-center/) | Use compact navigation and hide weather and screen-time until their required services are intentionally enabled. |
| Notifications and OSD | It can own the D-Bus notification service and present notification history. OSD has independent toggles for volume, brightness, Wi-Fi, Bluetooth, power profile, caffeine, night light, DND, lock keys, keyboard layout, media, and privacy capture state. [Notifications](https://docs.noctalia.dev/noctalia/services/notifications/) [OSD](https://docs.noctalia.dev/noctalia/configuration/shell/) | Use it instead of a separate notification daemon and OSD. Keep actions enabled and show at most a few simultaneous toasts. |
| Audio, media, network, power | Audio controls use the PipeWire/WirePlumber stack; the Control Center also exposes MPRIS media, NetworkManager, Bluetooth, UPower and power-profile functions when their services are present. [Audio](https://docs.noctalia.dev/noctalia/services/audio/) [Control Center tabs](https://docs.noctalia.dev/noctalia/control-center/) | Use Noctalia as UI only. Keep the existing system services as the authorities. Do not allow audio overdrive in the baseline. |
| Screenshots and privacy | It can take screenshots, copy and save them, freeze a region selection, send captures to an annotator command, and show microphone, camera, and screen-share activity. Filters can suppress named capture clients. [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/) | Use the OSD/privacy indicator if it replaces an overlapping existing indicator. Keep filters empty unless a known false positive needs a narrowly tested rule. |
| Theme and application templates | Themes can use built-in, wallpaper, community, or custom palettes. The shell can render templates for applications and has official templates for GTK/Qt, Emacs, and Umbriel, with community templates for several apps. [Theme](https://docs.noctalia.dev/noctalia/theming/) [App theming](https://docs.noctalia.dev/noctalia/theming/app-theming/) | Keep the repository's Stylix-generated custom palette as the source of truth. Do not enable application templates that overwrite a configuration already owned by Nix or Stylix. |
| Automation | IPC controls shell, surfaces, media/UI, system controls, and plugins. Hooks can run commands on startup, wallpaper/theme changes, session lock state, radio changes, and battery events. [IPC](https://docs.noctalia.dev/noctalia/ipc/) [Hooks](https://docs.noctalia.dev/noctalia/automation/hooks/) | Prefer compositor binds for input and Nix systemd timers/services for durable jobs. Use a hook only when it must follow a Noctalia event. |
| Accessibility and localization | Non-bar UI scaling and a high-contrast mode are available. The shell follows locale by default and supports a configured language, including right-to-left mirroring when a matching catalog exists. [Accessibility and locale](https://docs.noctalia.dev/noctalia/configuration/shell/) | Leave the scale at compositor defaults unless a real monitor test shows a need. Keep high contrast as an opt-in accessibility profile. |
| Calendar, weather, location, screen time | Calendar supports read-only CalDAV, iCloud, Google, and ICS accounts. Location feeds weather, night light, and automatic theme mode. Screen time tracks per-app usage when enabled. [Calendar](https://docs.noctalia.dev/noctalia/services/calendar/) [Location](https://docs.noctalia.dev/noctalia/services/location/) | Do not enable by default. Calendar and location add credentials or network/privacy choices. Screen-time adds tracking without much desktop value for this profile. |
| Desktop widgets | Clock, calendar, audio visualizers, weather, media player, buttons, stickers, labels, volume, and system-monitor widgets can be positioned through config or an editor. [Desktop widgets](https://docs.noctalia.dev/noctalia/desktop/widgets/) | Keep off. Add one only for an empty overview workspace after checking its update interval and visual impact. |
| Greeter | A separate Noctalia Greeter project integrates with greetd. It is not part of the shell's core ownership. [Project scope](https://github.com/noctalia-dev/noctalia#scope) | Do not change the display manager as part of this shell migration. |

## Ownership decisions for the requested features

### Wallpaper

Noctalia can browse a directory, set per-monitor images, rotate recursively, animate changes, support light/dark directories, and span one image across monitors. [Wallpaper and backdrop](https://docs.noctalia.dev/noctalia/desktop/wallpaper/)

That is not a good replacement for this repository's curated source fetchers and awww rotation. Keep the existing renderer and source manager. Noctalia officially supports this arrangement: disable `[wallpaper].enabled`, retain `theme.source = "wallpaper"` only when dynamic colors are wanted, then call `noctalia msg wallpaper-set <path>` whenever the external renderer changes the file. It extracts colors and cross-fades shell colors without drawing wallpaper itself. [External wallpaper FAQ](https://docs.noctalia.dev/noctalia/getting-started/faq/)

For the Carbon Neon palette, keep `theme.source = "custom"` instead. Wallpaper-derived colors would make the shell less consistent and make a rotating collection change the UI identity every 30 minutes. Noctalia wallpaper depth and video-wallpaper plugins are deliberately out of scope for a performance-first desktop. The official depth plugin downloads a local 99 MB model and the video plugin manages `mpvpaper` per output. [Official plugins](https://docs.noctalia.dev/noctalia/plugins/official-plugins/)

### Polkit

Noctalia has a native Polkit authentication agent, but upstream says to keep it disabled when another desktop agent handles prompts. [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/)

Keep the repository's existing `polkit-gnome-authentication-agent-1` and system policy. It already has a dedicated user unit and avoids changing the privilege boundary during a visual-shell migration. There must be exactly one session Polkit agent. Moving to Noctalia's agent is reasonable only after the existing agent is removed, an administrator action is tested on the real session, and the native prompt is preferred enough to justify that regression risk.

### Lock screen and idle

Noctalia's lock screen authenticates through the system `login` PAM service and normally acquires a logind sleep-delay inhibitor so it locks before suspend. Its idle service also supports lock, screen off, suspend, lock-and-suspend, custom commands, a pre-action fade, and Wayland idle inhibitors. [Lock and suspend FAQ](https://docs.noctalia.dev/noctalia/getting-started/faq/) [Idle service](https://docs.noctalia.dev/noctalia/services/idle/)

Keep Hyprlock and Hypridle. This repository already configures their PAM/keyring integration, lock-before-sleep ordering, and DPMS behavior. Two lock surfaces or two idle daemons invite timing bugs around suspend. Noctalia can still clear its encrypted clipboard through the existing lock command and receive the session state through hooks if a future integration needs it.

### Brightness and night light

Noctalia uses kernel backlight by default and can opt into `ddcutil` for external DDC/CI monitors. Per-monitor backend choices, a minimum brightness floor, monitor synchronization, and a cooldown after repeated DDC failures are available. [Brightness](https://docs.noctalia.dev/noctalia/services/brightness/)

Use Noctalia brightness as the single UI and media-key path if the laptop backlight works. Add `ddcutil` only after validating every connected external monitor, then set per-monitor backends and a nonzero floor to prevent an accidental black screen. Do not run a separate brightness OSD.

Noctalia night light uses `wlr-gamma-control`, follows the location schedule, and releases gamma control immediately when disabled. [Night Light](https://docs.noctalia.dev/noctalia/services/night-light/)

Use it instead of another gamma controller, but choose a fixed local sunrise/sunset schedule or manual coordinates. Do not use IP geolocation in a privacy-first baseline. The location service sends IP-based lookup through `noctalia.dev` when automatic location is enabled. [Location privacy behavior](https://docs.noctalia.dev/noctalia/services/location/)

### Dock

Noctalia's dock shows pinned and running applications, supports monitor targeting, auto-hide or smart auto-hide, workspace reservation, magnification, app-instance counts, drag reordering, and context-menu pinning. [Dock](https://docs.noctalia.dev/noctalia/dock/)

Leave it disabled. In a Hyprland setup with a launcher, workspaces, and a top bar, it duplicates navigation and consumes screen space. If a dock is wanted after daily use, use a bottom dock with `smart_auto_hide = true`, `reserve_space = false`, `show_running = true`, modest icons, no magnification, and explicit pins. This gets a useful empty-workspace launcher without permanent chrome.

### Plugins

Plugins provide bar or desktop widgets, panels, Control Center shortcuts, launcher providers, and headless services. Official and community git sources are enabled by default as sources, but a plugin is inactive until explicitly enabled. The official catalog currently includes screen recording, translation, countdown, Bongo Cat, Wallhaven browsing, wallpaper depth, video wallpaper, and a world clock. [Using plugins](https://docs.noctalia.dev/noctalia/plugins/) [Official plugins](https://docs.noctalia.dev/noctalia/plugins/official-plugins/)

Keep plugins opt-in and declarative where possible. Review the exact revision, dependencies, network access, and long-running work before enabling one. The only official plugin worth considering in this profile is screen recording, and only if it replaces the current recorder after a real portal/audio/HDR test. It uses `gpu-screen-recorder` and can run a replay buffer continuously, so it should not be in the baseline. [Official screen-recorder plugin](https://docs.noctalia.dev/noctalia/plugins/official-plugins/)

## Security, privacy, and performance settings

Use Secret Service storage for Noctalia's master key. Clipboard history is encrypted at rest with a purpose-specific key derived from that master key; if Secret Service is unavailable, Noctalia retains history only for the current session. Keep confirmation for clearing history and cap the unpinned history. Set automatic paste to off for a security-first profile, because selecting a history item otherwise may inject it into the focused application. [Encrypted clipboard storage](https://docs.noctalia.dev/noctalia/configuration/shell/)

Set `offline_mode = true`, `external_ip_enabled = false`, and `telemetry_enabled = false`. Offline mode blocks Noctalia's HTTP work, including weather, remote palettes/templates, album art, remote notification icons, and exchange-rate updates. [Shell privacy settings](https://docs.noctalia.dev/noctalia/configuration/shell/)

Enable `shared_gl_context = true`. The setting shares GPU textures across shell surfaces. Keep animations on but restrained, avoid transparent glass panels and a permanent video or wallpaper-depth service, and leave desktop widgets off. [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/)

Set `launch_apps_custom_command = "uwsm app -- $CMD"` to preserve the session model already used by the desktop. Consider `launch_apps_as_systemd_services = true` only after confirming Noctalia runs as a systemd user unit or through UWSM. Upstream says it gives apps their own cgroup and lets them survive shell restarts in that setup. [App launch behavior](https://docs.noctalia.dev/noctalia/configuration/shell/)

## Smaller features worth keeping or declining

- Keep the window switcher, workspace widget, active-window label, tray, session panel, media control, and keyboard-layout/lock-key OSDs. They are small, coherent shell surfaces and remove separate one-off utilities. [Widget index](https://docs.noctalia.dev/noctalia/bar/widgets/) [Shell IPC](https://docs.noctalia.dev/noctalia/ipc/)
- Keep screenshots only if Noctalia's region selection and existing annotation/upload workflow pass the portal test. Its native capture supports region or output capture, clipboard copy, saved images, cursor selection, remembered regions, and a pipe to an annotator. [Screenshot configuration](https://docs.noctalia.dev/noctalia/configuration/shell/)
- Keep custom dmenu launcher providers for a short, reviewed local command such as an SSH host picker. Do not make unreviewed shell snippets global launcher providers. [Launcher provider configuration](https://docs.noctalia.dev/noctalia/configuration/shell/)
- Leave hot corners and the cosmetic screen-corners overlay off. They add accidental activation risk or visual decoration without improving a keyboard-first Hyprland workflow. [Hot corners and screen corners](https://docs.noctalia.dev/noctalia/configuration/shell/)
- Keep bar auto-hide off. A fixed 34 px top bar has predictable targets and does not reserve much space. Use a solid, non-blurred bar with no shadow and attached Control Center panels to avoid fractional-scale seams. [Bar configuration](https://docs.noctalia.dev/noctalia/bar/) [Attached-panel guidance](https://docs.noctalia.dev/noctalia/getting-started/faq/)
- Do not enable weather, public-IP lookup, exchange-rate lookup, community palettes, or remote templates in the default profile. They need network access. Enable calendar only after choosing an account and Secret Service-backed credentials; Noctalia's calendar data is read-only. [Offline-mode behavior](https://docs.noctalia.dev/noctalia/configuration/shell/) [Calendar](https://docs.noctalia.dev/noctalia/services/calendar/)

## Validation gate

Before making Noctalia the only default shell, run `noctalia config validate` and test login, lock, lid-close suspend, wake, a Polkit prompt, Wi-Fi/Bluetooth, media keys, integrated and external brightness, night-light enable/disable, notification actions, tray, clipboard after an app exits, screenshot portal behavior, fractional scale, and monitor hotplug. The validator checks the merged file and GUI override layers that Noctalia actually loads. [Configuration validation](https://docs.noctalia.dev/noctalia/configuration/)

The GUI state override loads after handwritten TOML. For a Nix-managed configuration, inspect or remove conflicting keys from `~/.local/state/noctalia/settings.toml` before diagnosing a configuration issue. [Configuration precedence](https://docs.noctalia.dev/noctalia/configuration/)

## Source index

- [Noctalia v5 README](https://github.com/noctalia-dev/noctalia)
- [Noctalia documentation overview](https://docs.noctalia.dev/noctalia/)
- [Noctalia configuration](https://docs.noctalia.dev/noctalia/configuration/)
- [Shell configuration](https://docs.noctalia.dev/noctalia/configuration/shell/)
- [FAQ, including external wallpaper and lock behavior](https://docs.noctalia.dev/noctalia/getting-started/faq/)
- [Official plugins](https://docs.noctalia.dev/noctalia/plugins/official-plugins/)
