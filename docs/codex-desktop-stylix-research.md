# Codex Desktop and Stylix research

## Conclusion

Codex Desktop can be integrated cleanly with a Stylix-derived palette and the
configured sans-serif and monospace fonts. It has native appearance controls
for light, dark, and system modes; background, foreground, accent, contrast,
and semantic colors; UI and code fonts; font sizes; translucent sidebars; and
macOS font smoothing. No CSS injection or modification of the signed
application bundle is needed or recommended.

The public documentation describes the controls in the app, but it does not
publish the configuration-file schema for Desktop appearance. The locally
installed build does expose and persist that schema in the active Codex config,
so a Nix integration can be based on those values while keeping the generated
block deliberately small and easy to update.

## Officially supported Desktop controls

OpenAI's Settings reference says that **Settings > Appearance** supports a
base Light, Dark, or System theme; accent, background, and foreground colors;
UI and code fonts; custom-theme sharing; contrast; a translucent sidebar; and
separate UI/code font-size controls. System means "match your system." [OpenAI
Settings reference](https://learn.chatgpt.com/docs/reference/settings)

That is enough for a high-quality Stylix integration:

| Desktop role | Stylix source | Carbon Neon recommendation |
| --- | --- | --- |
| Background/surface | `config.lib.stylix.colors.base00` | `#0A0A0A` |
| Foreground/ink | `base05` | `#E6E6E6` |
| Accent | `base0D` | `#80CBC4` teal |
| Diff added | `base0B` | `#A3C679` green |
| Diff removed | `base08` | `#F07178` coral-red |
| Skill color | `base0E` | `#C792EA` violet |
| UI font | `config.stylix.fonts.sansSerif.name` | the configured Stylix sans font |
| Code font | `config.stylix.fonts.monospace.name` | the configured Stylix monospace font |

For the OLED Carbon theme, use a dark native appearance and an opaque window.
This avoids macOS material/transparency tinting the otherwise black surface.
The app also has a native macOS font-smoothing preference, which should remain
enabled unless visual inspection of the chosen font shows a problem.

## Local Desktop schema: verified, but not yet public API

The currently installed ChatGPT Desktop app (Codex view; build
`26.818.61809`) stores its active appearance state in
`/Users/ianmh/.config/codex/config.toml`. Its bundled implementation validates
these Desktop keys:

```toml
[desktop]
appearanceTheme = "system" # system, light, or dark
appearanceLightCodeThemeId = "codex"
appearanceDarkCodeThemeId = "codex"
appearanceDiffMarkerStyle = "color" # color or symbols
sansFontSize = 14 # permitted range: 11–16
codeFontSize = 12 # permitted range: 8–24
useFontSmoothing = true

[desktop.appearanceDarkChromeTheme]
surface = "#0A0A0A"
ink = "#E6E6E6"
accent = "#80CBC4"
contrast = 60 # integer range: 0–100
opaqueWindows = true

[desktop.appearanceDarkChromeTheme.fonts]
ui = "<Stylix sans-serif family>"
code = "<Stylix monospace family>"

[desktop.appearanceDarkChromeTheme.semanticColors]
diffAdded = "#A3C679"
diffRemoved = "#F07178"
skill = "#C792EA"
```

The same `ChromeTheme` shape exists for
`desktop.appearanceLightChromeTheme`. The local schema requires six-digit hex
colors, supports only the stated numeric ranges, and has separate UI and code
font values (plus internal face metadata when chosen through the UI). This was
verified from the signed, locally installed application resource at
`/Users/ianmh/Applications/Home Manager Apps/ChatGPT.app/Contents/Resources/app.asar`.
It is useful implementation evidence, not a promised public configuration API.

The current config already contains a dark Chrome-theme block, confirming that
the Desktop app reads this config location in this installation. Do not replace
the whole file: it also contains user-selected settings, project trust records,
and runtime-managed state.

## What not to conflate

The public Codex configuration documentation describes user configuration as
`$CODEX_HOME/config.toml` and explains configuration layers used by the CLI and
IDE extension. [Configuration basics](https://learn.chatgpt.com/docs/config-file/config-basic)
Its documented `tui.theme` field is explicitly a terminal syntax-highlighting
theme, not the Desktop application’s UI palette or fonts. [Configuration
reference](https://learn.chatgpt.com/docs/config-file/config-reference)

Consequently:

- Do not expect `stylix.targets` or `tui.theme` to style Codex Desktop.
- Do not patch `app.asar`, inject CSS through the debugging protocol, or
  re-sign the app. Those approaches are unsupported and update-fragile.
- Do not force a full declarative replacement of `config.toml`; the Desktop app
  writes user state to it.

## Safe Nix integration plan

1. Add a focused Codex Desktop appearance module next to
   `modules/home/dev/agentic-gui/codex-app.nix`.
2. Generate only the `[desktop]` appearance keys and two chrome-theme tables
   from the selected `appearance.theme` and Stylix palette/font values. Merge
   them with the existing managed Codex settings rather than taking ownership
   of the entire config file.
3. Generate **both** light and dark Chrome themes so System mode has a defined
   result. Use the selected Carbon theme’s dark palette for the default; derive
   a readable light counterpart only if System switching is desired. Otherwise
   choose `appearanceTheme = "dark"` for a deterministic Carbon Neon desktop.
4. Select an existing built-in code-theme identifier through
   `appearanceDarkCodeThemeId` / `appearanceLightCodeThemeId`; these identifiers
   affect code syntax only. The app’s native custom Chrome colors remain the
   system-wide visual integration.
5. Keep `opaqueWindows = true` for Carbon Neon and Carbon Neon OLED, then
   restart Codex Desktop after a Home Manager switch to reload the appearance.

Because the appearance-file schema is currently undocumented, retain the
module as a small compatibility boundary and verify the configuration after
each Desktop update. The supported in-app fallback is to use **Settings >
Appearance** to set the same colors and fonts or import a custom theme.
