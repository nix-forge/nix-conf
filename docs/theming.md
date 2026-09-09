# Theming with Stylix targets

Select the shared `stylix` feature alongside applications in a host or home
profile. It imports the local target layer automatically. Application modules
own installation, service behavior, keybindings, and security policy. Theme
modules own palettes, fonts, CSS, theme extensions, and appearance updates.

The [research and design rationale](stylix-target-layer-research.md) records the
pinned Stylix contracts used by this layer.

## Choose a theme

Set the host's theme in its local configuration:

```nix
{
  appearance.theme = "carbon-neon-oled";
}
```

The available values are `carbon-neon`, `carbon-neon-oled`, `catppuccin-mocha`,
and `gruvbox-dark-medium`. Attached homes inherit the host selection and global
Stylix enable defaults. A home can override these explicitly. Standalone homes
default to Carbon Neon.

`appearance.palette` supplies shared semantic colors derived from Stylix. It is
read-only. Font roles and sizes remain under `stylix.fonts`.

## Control individual targets

The existing Stylix controls apply to local targets too:

```nix
{
  # Disable all styling, keeping applications enabled.
  stylix.enable = false;
}
```

To opt in selectively, set these in the home profile:

```nix
{
  stylix.autoEnable = false;
  stylix.targets.codex-desktop.enable = true;
  stylix.targets.vscode.enable = true;
}
```

Targets write application files only when the application or corresponding
`desktop` feature is enabled. Enabling a theme target does not install or start
an application. System Chromium policies have their own target because the
host owns those policies.

For integrations that extend or replace upstream styling, `custom.enable`
controls the repository's additions:

```nix
{
  # Use upstream Stylix's VS Code theme and fonts.
  stylix.targets.vscode.custom.enable = false;

  # Apply the custom theme to this VS Code profile.
  stylix.targets.vscode.profileNames = [ "work" ];

  # Disable both upstream and custom Ghostty styling.
  stylix.targets.ghostty.enable = false;
}
```

| Target | Local behavior |
| --- | --- |
| `vscode` | Native theme extensions, icons, cursor styling, and terminal font fallback |
| `spicetify` | Native Spotify theme and Carbon CSS |
| `noctalia` | Palette, visual settings, dock styling, and optional icon synchronization |
| `ghostty` | Selection colors and platform font fallback policy |
| `hyprland` | Borders, spacing, and decoration |
| `hyprlock` | Input-field appearance |
| `codex-desktop` | Native desktop appearance preferences |
| `hyprshell` | Window-switcher CSS |
| `ironbar` | Panel CSS and icon theme |
| `swaync` | Notification CSS for `desktop.notifications` |
| `swayosd` | On-screen display CSS |
| `walker` | Launcher CSS and theme selection |
| `firefox`, `zen-browser` | Upstream browser profile setup |
| `browser-suite` | Home-managed Chromium theme extension selection |
| `chromium-policies` | System-managed Chromium theme extension selection |

The first six targets expose `custom.enable`. For native replacements, component
switches such as `stylix.targets.spicetify.colors.enable` control the upstream
renderer. The custom renderer disables replaced components by default. Use
`custom.enable = false` to restore the upstream renderer; use the target's
`enable = false` to disable both. Do not enable two competing renderers for the
same theme setting.

VS Code retains upstream fonts. At the pinned revision, that font component also
sets the color-theme name, so the custom target narrowly forces that one setting.
Disable the custom target before choosing a different VS Code color theme.
Ghostty and Hyprland also retain documented overrides of upstream defaults.

Theme opt-out removes declaratively managed theme files at the next Home Manager
activation. Applications then use their remaining configuration or defaults.
Codex's appearance updater edits a mutable file, so opt-out stops future updates
and leaves the last applied appearance intact. It does not reset application
preferences. Restart an application when its theme format requires it.

## File layout

[The shared Stylix module](../modules/shared/stylix/default.nix) owns theme selection,
semantic colors, font roles, and platform integration. It imports
[`modules/shared/stylix/home.nix`](../modules/shared/stylix/home.nix) for homes and discovers matching system targets for NixOS and Darwin.

Each application has a directory under `modules/shared/stylix/targets/`. Its `home.nix` is the
Home Manager target, `system.nix` is used for system policies where needed, and
its assets and pure rendering helpers live beside it. The shared `default.nix`
exports `nixos`, `darwin`, and `homeManager` modules, preserving the `stylix`
feature name. Each target exports the matching platform class. Pure rendering
helpers expose `render`, which shared-module discovery ignores. The framework
discovers matching platform exports recursively, so additions, moves, and removals
need no second import list. Home Manager inherits host theme and enable defaults
through `osConfig`; standalone homes retain their existing defaults.

The existing `stylix-targets-firefox` and `stylix-targets-zen-browser` feature
names now come from shared target discovery. Stable module keys prevent duplicate
configuration when a profile also selects `stylix`, which imports every target.

## Add or change a target

1. Check the pinned upstream target first. Extend it if its output is suitable.
   Add a custom renderer only for a concrete difference in application behavior.
2. Add `modules/shared/stylix/targets/<application>/home.nix`.
   Export the Home Manager module as `homeManager`; discovery imports that class.
   Keep assets in the same directory. For a new target, declare its enable option
   with `config.lib.stylix.mkEnableTarget "Application" true`.
3. Guard custom output with `stylix.enable`, the target enable switch, and the
   application enable option. Guard references to optional third-party modules
   using option presence. Keep imports independent of evaluated configuration.
4. Use structured application options and ordinary defaults where possible.
   Explain any forced override beside the setting. Keep generated files in
   derivations and avoid reading derivations during evaluation.
5. Exercise the public controls in
   [`tests/nix/theme-targets.nix`](../tests/nix/theme-targets.nix). For serialized
   files, extend the relevant generated-file check.

No new daemon, privileged operation, telemetry, or update channel is introduced
by this layer. Existing package pins and runtime preference safeguards remain
in place. Noctalia's application module keeps its privacy policy and disables
mutable theme-template writers even when custom theming is off.

Run the focused checks with:

```sh
nix build .#checks.x86_64-linux.theme-targets \
  .#checks.x86_64-linux.template-configs --no-link
nix eval --raw .#checks.aarch64-darwin.theme-targets.drvPath
```

The second command evaluates Darwin behavior; it does not run Darwin software.
Follow the repository's desktop build-placement rule for a full system build.
