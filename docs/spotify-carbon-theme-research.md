# Spotify Carbon Neon theming research

## Verdict

The current Carbon Neon Spotify setup is only partly themed. The black shell and most text match the system palette, but the bright purple Liked Songs header and lime playback accents do not. They are not a sign that Spicetify failed to run. They show the limit of using a generated colour scheme with the stock Spicetify layout and no Carbon-specific CSS.

The right fix is an original local Spicetify theme with a complete Carbon colour scheme and a small, selector-tested `user.css`. Do not replace it with an unrelated third-party visual theme. Carbon needs its own restrained overlay that removes Spotify's artwork gradients and reserves teal for the interactive accent.

## What the screenshot is showing

The purple Liked Songs block is a Spotify entity-header gradient based on its artwork. It is not one of the standard Spicetify colour roles. Spicetify has 19 palette roles, including `main`, `card`, `button`, and `button-active`, but none for an image-derived or page-header gradient. See Spicetify's [colour-role source](https://github.com/spicetify/cli/blob/main/src/utils/color.go#L15-L56).

The lime play button, current track number, check mark, and playlist state are explained by the present Carbon mapping in [`modules/home/spotify.nix`](../modules/home/spotify.nix): it assigns `button-active` to Carbon's green `base0B`. Spicetify documents that `button-active` controls the active play button, while `button` is also used for the playing track and like button. [Default-theme colour-role comments](https://github.com/spicetify/cli/blob/main/Themes/SpicetifyDefault/color.ini#L1-L18)

The current configuration supplies 16 of Spicetify's 19 roles. It leaves `main-elevated`, `highlight`, and `highlight-elevated` unspecified. A complete Carbon scheme should set every role directly, even where the values intentionally repeat. This keeps raised surfaces and hover states coherent as Spotify changes its UI.

## Why a colour scheme cannot finish this job

Spicetify converts `color.ini` values into CSS variables. Its own documentation identifies `user.css` as the mechanism for visual UI changes. [Theme development guide](https://spicetify.app/docs/development/themes)

`replace_colors` is deliberately narrower than a full recolouring engine. Its current source replaces a fixed set of known legacy literals such as Spotify black, green, blue, and a few RGBA or HSLA forms. A runtime or artwork-derived gradient does not have to contain one of those literals, so it can survive unchanged. [Colour replacement implementation](https://github.com/spicetify/cli/blob/main/src/preprocess/preprocess.go#L316-L473)

Spicetify injects `colors.css` before `user.css`, so a theme stylesheet can intentionally override a gradient while retaining the generated palette variables. [Injection order](https://github.com/spicetify/cli/blob/main/src/preprocess/preprocess.go#L278-L290) The upstream default theme uses exactly this technique. It unsets entity-header and action-bar background images, then supplies a neutral entity-header overlay based on `--spice-main`. [Default theme stylesheet](https://github.com/spicetify/cli/blob/main/Themes/SpicetifyDefault/user.css#L20-L28) [Entity-header overlay](https://github.com/spicetify/cli/blob/main/Themes/SpicetifyDefault/user.css#L73-L93)

Stylix has no direct Spotify desktop-client target in the pinned source. In this configuration, [`modules/home/spotify.nix`](../modules/home/spotify.nix) correctly derives Spicetify colours from `config.lib.stylix.colors`, but that is a palette bridge, not a full Spotify UI theme.

## Recommended Carbon mapping

Use teal as the one persistent interactive colour. The Carbon green remains available for semantic success states, not ordinary playback or selection. That makes the interface read as one system instead of alternating between teal and Spotify-like green.

| Spicetify role | Carbon Neon value | Purpose |
| --- | --- | --- |
| `main` | `base00` | Main canvas |
| `main-elevated` | `base01` | Raised canvas |
| `highlight` | `base01` | Hover on the canvas |
| `highlight-elevated` | `base02` | Hover on raised surfaces |
| `sidebar` | `base00` | Library pane |
| `player` | `base00` | Playback bar |
| `card` | `base02` | Cards and focused surfaces |
| `shadow` | `000000` | Shadows |
| `selected-row` | `base04` | Quiet selected-row text and chrome |
| `button` | `base0D` | Teal play, like, active track, and primary controls |
| `button-active` | `base0D` | Teal pressed and playing state |
| `button-disabled` | `base03` | Inactive sliders |
| `tab-active` | `base02` | Selected tabs |
| `text` | `base05` | Primary text |
| `subtext` | `base04` | Secondary text |
| `notification` | `base0D` | Informational toast |
| `notification-error` | `base08` | Error toast |
| `misc` | `base04` | Muted UI chrome |

For Carbon Neon OLED, use the same mapping with its true-black `base00`. Keep raised surfaces on `base01` and `base02`; pure black should not be the only visible surface.

## The CSS scope to add

Keep the custom CSS short and visual. It should:

- Remove image and gradient backgrounds on `.main-entityHeader-*`, `.x-entityHeader-overlay`, and action-bar background elements.
- Set the entity-header overlay to `var(--spice-main)` rather than a coloured artwork wash.
- Use `var(--spice-button)` for the playing-row marker, active playback controls, and progress fill.
- Use `var(--spice-highlight)` and `var(--spice-highlight-elevated)` for hover states.
- Avoid layout changes, font replacement, blur, and animation. Those are the parts most likely to rot after a Spotify update.

The selectors should be checked with Spotify DevTools before being committed. Spicetify officially supports `enable-devtools`; its CLI then supports applying changes and reloading the client. [CLI commands](https://spicetify.app/docs/cli/commands)

## High-quality theme review

Catppuccin remains the strongest ready-made choice when the selected system theme is Catppuccin. It has a dedicated upstream Spicetify repository with its own full stylesheet, so it controls more than the palette roles. [Catppuccin Spicetify stylesheet](https://github.com/catppuccin/spicetify/blob/main/catppuccin/user.css)

For Carbon Neon, the best foundation is Spicetify's maintained default presentation plus a Carbon overlay. The upstream default stylesheet already handles the exact class of header-gradient problem visible in the screenshot. [Default stylesheet](https://github.com/spicetify/cli/blob/main/Themes/SpicetifyDefault/user.css)

Sleek is a useful reference for a polished, CSS-led theme. Its stylesheet deliberately controls top-bar gradients, navigation states, playback behavior, and active elements through `--spice-*` variables. It is a good example of scope, but its rounded, gradient-heavy visual language conflicts with Carbon's near-black minimalism. [Sleek stylesheet](https://github.com/spicetify/spicetify-themes/blob/master/Sleek/user.css)

The official Spicetify documentation lists Dribbblish Dynamic and Nord among themes that may not work with current Spotify releases. Avoid making either the Carbon foundation. [Theme compatibility note](https://spicetify.app/docs/customization/themes)

## Declarative implementation path

1. Add a local `CarbonNeon` Spicetify theme source with `color.ini` and `user.css`.
2. Generate all 19 values in its `[custom]` scheme from `config.lib.stylix.colors` and select it only for the two Carbon variants.
3. Keep the current packaged Catppuccin and Gruvbox themes unchanged.
4. Use a small CSS regression check after Spotify updates. If a selector changes, update only that rule rather than broadening the stylesheet.

This keeps the theme fully declarative in Nix, avoids copied third-party theme assets, and fixes the visual mismatch shown in the screenshot.
