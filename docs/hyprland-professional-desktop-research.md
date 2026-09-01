# Professional Hyprland desktop research

## Decision

Do not copy a competition rice or replace this configuration with a monolithic dotfiles repository. The visual problem is real, but the session, portal, power, and security layers already have the right ownership. Replace the four overlapping visible shell surfaces as one unit only after a controlled pilot.

The best candidate is **Noctalia v5**, evaluated as an opt-in desktop-shell profile. It owns the bar, dock, launcher, control centre, notifications, OSD, session panel, tray, wallpaper surface, and desktop widgets under one settings, palette, component, and IPC system. Its upstream description explicitly targets the problem of a desktop assembled from separate bar, launcher, notification, lock, wallpaper, and script layers. It supports Hyprland and multi-monitor surfaces. [Noctalia README](https://github.com/noctalia-dev/noctalia#why-noctalia) [feature list](https://github.com/noctalia-dev/noctalia#what-it-includes)

Do **not** give Noctalia ownership of the current lock and idle path yet. Keep UWSM, Hyprland, XDG Desktop Portal Hyprland, PipeWire, WirePlumber, Hypridle, Hyprlock, the wallpaper downloader, and existing capture stack. That preserves the parts which are both security-sensitive and already tested. Noctalia v5 is still beta and recent releases include Hyprland workspace, hotplug, and autohide fixes, so it needs a real-monitor pilot before it becomes the default. [Noctalia releases](https://github.com/noctalia-dev/noctalia/releases)

## What strong rices actually teach

The Hyprland project lists ML4W, JaKooLit, end-4, HyDE, Omarchy, and Dank Linux as preconfigured desktop-like setups. The list is useful for finding patterns, not for copying a configuration wholesale. [Hyprland's preconfigured setups](https://wiki.hypr.land/Getting-Started/Preconfigured-setups/)

The useful patterns are clear:

- One shell owns the visible desktop. DankMaterialShell packages bar, launcher, notifications, lock, idle, policy agent, and related desktop pieces together. [DankMaterialShell README](https://github.com/AvengeMedia/DankMaterialShell)
- The shell has an explicit component system. Caelestia exposes a common shell, per-monitor settings, design tokens for rounding, spacing, type, and animation, plus an IPC interface. [Caelestia shell configuration](https://github.com/caelestia-dots/shell#configuring)
- Wallpaper-derived palettes work only when every surface consumes the same semantic palette. Noctalia and DankMaterialShell both treat theming as a shell concern rather than as unrelated CSS files. [Noctalia README](https://github.com/noctalia-dev/noctalia) [DankMaterialShell installation](https://github.com/AvengeMedia/DankLinux-Docs/blob/master/docs/dankmaterialshell/installation.mdx)
- Good screenshots use sparse information density, a restrained accent colour, consistent iconography, and obvious hierarchy. They do not need permanent docks, high-saturation gradients, animated borders, or every metric visible in the bar.

Competition results should not drive the architecture. The r/unixporn organisers described their contest as screenshot-only, selected by community upvotes, and a moderator answered that it only needed to "look stunning." That rewards a frame, not sleep-resume, screen sharing, keyboard navigation, notification actions, multi-monitor placement, or a maintainable Nix deployment. [r/unixporn competition rules](https://www.reddit.com/r/unixporn/comments/ounm70)

## Review of the current desktop

The current desktop has a coherent *palette* but not a coherent *design system*.

`Carbon Neon` itself is a good base for a professional dark desktop: near-black surfaces, light neutral text, muted grey, and a single aqua accent. The weak point is that the current visible apps apply the Base16 colours directly, each with separately invented geometry:

| Surface | Current geometry | Why it reads as assembled |
| --- | --- | --- |
| Ironbar | 40 px high, 10 px top margin, 14 px shell radius, 10 px controls | A floating pill panel with dense 14 px controls. |
| Walker | 18 px shell radius, 12 px input and results, 16 px padding, 15 px type | The largest radius and a different type scale make it feel like another product. |
| SwayNC | 16 px shell radius, 12 px cards, 10 px padding, 14 px type | It nearly matches the others but follows another spacing scale. |
| SwayOSD | 16 px radius, 14 by 18 px padding, 16 px type | This is visually heavier than the panel controls it reports on. |
| Hyprland / Hyprlock | 14 px window and input rounding, 6 / 12 px gaps | Its values are close, but they are not derived from a shared component scale. |

The result is not a single bad choice. It is many reasonable local choices. Stylix cannot solve that alone because it applies colours, fonts, and wallpaper to supported targets, not shared shell layout, component behaviours, or visual hierarchy. [Stylix README](https://github.com/nix-community/stylix) Ironbar, Walker, and SwayNC each have their own styling systems. SwayNC documents that it is tested with default GTK Adwaita and its schema defaults `ignore-gtk-theme` to true, which is a practical sign that its look cannot be centrally governed through GTK theming. [Ironbar](https://github.com/JakeStanger/ironbar) [Walker](https://github.com/abenz1267/walker) [SwayNC](https://github.com/ErikReider/SwayNotificationCenter) [SwayNC schema](https://github.com/ErikReider/SwayNotificationCenter/blob/main/src/configSchema.json)

There are two operational issues too:

- Ironbar exposes both a menu button and a power popup in an already dense panel. It has music, volume, network, Bluetooth, notifications, tray, focused title, workspaces, and clock competing for attention.
- The desktop has four independently styled high-frequency surfaces. A small CSS change can improve one without improving the rest, which explains why repeated theming work has not made the desktop feel designed.

## Design standard for this desktop

The target should be quiet, desktop-first, and closer to macOS or modern GNOME than to a gamer dashboard. The Carbon Neon aqua is a state indicator and focus colour, not a decoration placed on every control.

Use these rules whether the GTK stack is refined or a cohesive shell is adopted:

1. **Three surface levels.** `base00` for background, `base01` for raised containers, and `base02` only for hover or selected containers. Do not give every item its own card border.
2. **One accent rule.** `base0D` identifies the active workspace, focused control, selection, progress, and keyboard focus. Status colours remain semantic: red only for destructive/error, yellow for warning, green for successful or enabled state.
3. **An 8 px spacing grid.** Use 4 px only for internal icon-to-label gaps. Use 8, 12, 16, 24, and 32 px everywhere else. A panel item should have at least a 32 by 32 px pointer target.
4. **Two radius values.** Use 10 px for compact controls and 16 px for a panel, popover, notification, launcher, or lock input. Full radius remains for badges, switches, and sliders only.
5. **One type system.** Inter at 13 px regular for utility information and 14 px medium for interactive labels. Reserve 16 px semibold for titles. Use a separate icon font only for icons, with consistent optical size and no mixed Nerd Font and Material glyph language.
6. **One elevation model.** The panel may use a 1 px low-contrast outline. Menus, launcher, notification centre, and lock surface may use one shadow. Inline cards do not need both an outline and a shadow.
7. **Motion communicates state.** Use 160 to 220 ms opacity or position transitions. Avoid continuous border animations, always-on blur, and spring effects which obscure state or consume power. Hyprland specifically warns that looping `borderangle` renders continuously at refresh rate. [Hyprland animations](https://wiki.hypr.land/Configuring/Animations/)
8. **Keyboard, contrast, and reduced-motion checks are release gates.** Material's token guidance is useful here: semantic roles keep colour choices tied to function and reduce accessibility mistakes. [Material 3 theme guidance](https://developer.android.com/codelabs/m3-design-theming)

This is a deliberate Carbon Neon system, not a generic Catppuccin or wallpaper-reactive clone.

## Stack comparison

| Option | Fit | Risk | Recommendation |
| --- | --- | --- | --- |
| Refine Ironbar + Walker + SwayNC + SwayOSD | Lowest migration cost. Retains all current behaviour. | Separate GTK CSS and component schemas will remain. Visual parity takes ongoing effort. | Keep as a supported fallback profile. |
| Noctalia v5 | The strongest direct answer to the inconsistency. Nix package and Home Manager module exist. It owns the overlapping visible surfaces and supports Hyprland. | Beta maturity. Its own visual language may need Carbon Neon token mapping. | Build an opt-in pilot, then promote only after full hardware tests. |
| DankMaterialShell | A credible Material 3 shell with Nix support, a clear component split, and optional features. | It explicitly replaces the lock, idle, policy agent, and other tools that we should retain for now. | Keep as a design reference and secondary pilot, not the first integration. |
| Caelestia | Excellent visual reference for motion, per-monitor settings, and tokens. It has an upstream Nix module. | Requires `quickshell-git` and maintains a large, rapidly moving stack. The project calls its git package unstable. | Do not adopt as the base desktop. Borrow its token discipline only. |
| end-4 / illogical-impulse | Influential Material 3 Quickshell rice and official Hyprland recommendation. | Upstream documents Nix support as work in progress and has had Quickshell compatibility pinning problems. | Use as visual reference, not a deployment dependency. |
| HyDE / JaKooLit / ML4W | Useful source of interaction ideas and onboarding. | Their installer and copy/restore model conflicts with this repository's declarative, auditable Nix ownership. JaKooLit is also in project handoff. | Do not import. |

Noctalia has an official NixOS path and a Home Manager module that accepts declarative settings. [Noctalia NixOS documentation](https://docs.noctalia.dev/noctalia/getting-started/nixos/) DankMaterialShell also offers a Home Manager module, but its Hyprland startup notes assume manual environment export. This repository's UWSM setup already handles that better. [DankMaterialShell installation](https://github.com/AvengeMedia/DankLinux-Docs/blob/master/docs/dankmaterialshell/installation.mdx)

Quickshell is not the first recommendation for a bespoke build. It is a capable QtQuick shell toolkit with Hyprland, PipeWire, PAM, tray, MPRIS, UPower, and policy-power support, but its project explicitly develops rapidly and package/Qt ABI mismatches can crash. A custom shell would create a second software product inside this Nix repository. [Quickshell overview](https://quickshell.outfoxxed.me/docs/about) [Quickshell build requirements](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md)

## Recommended implementation sequence

1. Add `desktop.shell.profile = "gtk" | "noctalia"`, defaulting to `"gtk"`. The profile must be exclusive. Never run Ironbar and a Noctalia bar, or SwayNC and a Noctalia notification daemon, together.
2. Factor the Carbon Neon desktop values into named design tokens before touching a shell. The Nix module should export surface roles, semantic state roles, two radii, spacing, type sizes, animation durations, and icon family. Keep plaintext templates outside Nix and render them with `replaceVarsWith`.
3. Reduce the GTK fallback to one 40 to 44 px panel. Keep workspace state, a short focused-window label, clock, network, audio, battery where applicable, notification state, and tray. Move media, output selection, and power actions into a single control centre. Remove duplicate menu affordances.
4. Add Noctalia as an opt-in input pinned in `flake.lock`, map Carbon Neon to its semantic palette, and disable only Ironbar, Walker, SwayNC, and SwayOSD. Keep Hyprlock and Hypridle. Keep the current wallpaper source manager as the owner of acquisition and rotation.
5. Test feature parity on the real monitor: fractional scaling, hotplug, sleep and lock race, multi-monitor focus, portal screen sharing, notification action activation, tray, media keys, brightness, DND, keyboard-only launcher, IME, and colour/contrast at 100% and 150% scale.
6. Take repeatable screenshots and inspect side-by-side. Reject the profile if spacing, type, active states, lock handoff, or key actions differ across surfaces. Only then make it the default.

## Sources checked

- [Hyprland preconfigured setups](https://wiki.hypr.land/Getting-Started/Preconfigured-setups/)
- [Noctalia source and feature ownership](https://github.com/noctalia-dev/noctalia)
- [Noctalia NixOS integration](https://docs.noctalia.dev/noctalia/getting-started/nixos/)
- [DankMaterialShell source](https://github.com/AvengeMedia/DankMaterialShell)
- [Caelestia source and configuration](https://github.com/caelestia-dots/shell)
- [end-4 Nix status](https://github.com/end-4/dots-hyprland/tree/main/sdata/dist-nix)
- [HyDE source](https://github.com/HyDE-Project/HyDE)
- [r/unixporn competition rules](https://www.reddit.com/r/unixporn/comments/ounm70)
- [Hyprland UWSM guidance](https://wiki.hypr.land/Useful-Utilities/Systemd-start/)
- [Material 3 theme guidance](https://developer.android.com/codelabs/m3-design-theming)
- [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/guidelines.html)
