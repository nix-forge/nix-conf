# Stylix themes worth using across a desktop

## Short answer

Use **Catppuccin Mocha** first. It is the strongest all-round choice for this
configuration. Stylix can apply its Base16 scheme to its supported targets, and
Catppuccin has a disciplined upstream palette plus a large, curated native-port
catalogue for applications that need more than a Base16 translation. The
recommended path is:

```nix
inputs.stylix.inputs.tinted-schemes + "/base16/catppuccin-mocha.yaml"
```

For a darker, higher-contrast alternative, use **Gruvbox dark, medium**. For a
cooler and quieter desktop, use **Nord**. **Dracula** is the best choice when
the priority is finding an existing native theme for an unusual application.

"Best looking" is personal. This note weighs a maintained canonical palette, a
real Base16 scheme in the Tinted collection, and credible native ports outside
Stylix. It does not treat stars or screenshots as evidence.

## What "works across applications" means in Stylix

The choice of a valid Base16 scheme does not change Stylix's application
coverage. Stylix reads the configured scheme and writes colours into each
enabled target. Its documentation explicitly accepts Tinted schemes, exposes
the computed colours for custom targets, and enables a target automatically
when the relevant program is installed. The current module tree includes GTK,
Qt, Firefox and Zen Browser, Wayland compositors and bars, common terminals,
editors, shell tools, and launchers. See the [Stylix configuration
guide](https://nix-community.github.io/stylix/configuration.html) and the
[current target modules](https://github.com/nix-community/stylix/tree/master/modules).

That creates two useful tiers of coverage:

1. **Stylix coverage.** Every recommendation below has a Base16 YAML file in
   the Tinted collection, so it can colour the same Stylix targets.
2. **Native-port coverage.** Browser user CSS, Electron applications, IDEs,
   and programs without a Stylix target can need their own theme. This is where
   Catppuccin, Dracula, and Nord pull ahead.

No scheme reaches every application automatically. A Base16 palette also
cannot preserve every role in a theme with more than sixteen named colours.
For applications where the exact upstream theme matters, use the matching
native port and keep its flavour aligned with the Stylix scheme.

## Ranking

### 1. Catppuccin Mocha

This is the best default. Mocha has dark, softly separated surfaces, readable
light text, and restrained pastel accents. It looks coherent in terminals,
GTK and Qt widgets, panels, and code without making the desktop feel loud.
The [Tinted scheme](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/catppuccin-mocha.yaml)
maps Catppuccin's canonical `base`, `mantle`, `surface`, `text`, and accent
colours into Base16. Catppuccin's own [style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
defines how those named colours should be used, and its [main project](https://github.com/catppuccin/catppuccin)
publishes a curated port list across editors, terminals, shells, browsers, and
other applications.

Choose **Macchiato** if Mocha feels a little too purple. Choose **Latte** only
for a deliberately light desktop, then set `stylix.polarity = "light"` as
well. The Tinted collection ships all three files:
[Mocha](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/catppuccin-mocha.yaml),
[Macchiato](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/catppuccin-macchiato.yaml),
and [Latte](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/catppuccin-latte.yaml).

### 2. Dracula

Pick Dracula when native application coverage matters more than having subtle
desktop accents. It is bold, high contrast, and immediately recognisable. The
[official Dracula project](https://github.com/dracula/dracula-theme) documents
themes for 400 or more applications, records the palette, and states that its
foreground and background meet WCAG 2.1 AA contrast. Its [Tinted Base16
scheme](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/dracula.yaml)
is present and identifies the upstream Dracula specification it follows.

The trade-off is visual intensity. Pink and purple accents become prominent in
window controls, prompts, and notifications. Most of its 400 or more ports are
community contributions, so breadth does not guarantee that every individual
port is equally polished. I would use it for a workstation that spends most of
its time in editors and terminals, not for a low-key GNOME or Hyprland desktop.

### 3. Gruvbox dark, medium

Gruvbox is the best warm, high-contrast alternative. Its earthy background and
cream foreground stay readable on less polished terminal and TUI targets. This
is also the only recommendation that Stylix uses in its own configuration
example, albeit with the hard variant. See [the Stylix example](https://nix-community.github.io/stylix/configuration.html)
and the [Tinted medium scheme](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/gruvbox-dark-medium.yaml).

The upstream [Gruvbox project](https://github.com/morhetz/gruvbox) documents
the palette, editor integration, and a separate contributions repository for
ports. It has a healthy ecosystem, but it does not provide the same central,
curated cross-application catalogue as Catppuccin or Dracula. For this reason
it ranks below them despite looking excellent under Stylix.

### 4. Nord

Nord is the calm option. Its blue-grey background ramp and desaturated accents
are easy to live with for long sessions. The [official Nord palette](https://github.com/nordtheme/nord)
defines sixteen named terminal-compatible colours, explains their syntax roles,
and links official port projects. The [Tinted Nord scheme](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/nord.yaml)
matches that palette.

Nord gives up some visual distinction compared with Catppuccin and Dracula,
especially for warnings and errors in small UI controls. It is still a very
good choice when consistency and low visual noise matter more than colourful
syntax.

### 5. Tokyo Night Storm

Tokyo Night Storm has a polished deep-blue look and works well for a
developer-heavy setup. Its [Tinted scheme](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/tokyo-night-storm.yaml)
is available. The upstream [Tokyo Night project](https://github.com/folke/tokyonight.nvim)
has a serious Neovim implementation and checked-in extras for other tools,
including terminals, shell, notifications, and Discord.

It ranks fifth because that upstream starts with Neovim rather than the whole
desktop. It is a fine personal choice, but not the safest recommendation for
universal native-port coverage.

## Recommendation for this repository

The shared Stylix module currently uses the Tinted scheme input directly, so
switching colours only requires changing the filename in
`modules/shared/stylix.nix`. Keep `polarity = "dark"` for the five dark
recommendations above. Start with Catppuccin Mocha, rebuild, then check the
applications that matter most here: Firefox or Zen Browser, the terminal,
Hyprland and Waybar, VS Code or the chosen editor, and Spotify. Add native
ports only where the Base16-rendered result is visibly weaker than the theme's
own implementation.

The existing Pop scheme remains a sound neutral fallback. It simply has far
less evidence of a maintained, cross-application native-theme ecosystem than
the choices above.
