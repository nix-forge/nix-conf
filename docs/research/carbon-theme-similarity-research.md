# Themes closest to Vira Carbon

## Short answer

There is no ready-made, maintained theme that combines all of Vira Carbon's
important traits: neutral `#0A0A0A` black, its shallow graphite surface ramp,
teal `#80CBC4` for interaction, and a subdued but broad syntax rainbow.

The best ready-made trial is **OneDark Dark** if true black and colourful code
matter most. **Ayu Dark** is the better trial if teal and near-black surfaces
matter more. Neither is a clean system-wide Carbon match. I would make an
original **Carbon Neon** Base16 scheme and use well-maintained native themes
only where they genuinely fit.

The proposed custom scheme should keep the verified Carbon colours as its
visual reference but should not reuse Vira assets, icons, theme files, or
branding. The Vira extension is commercial.

## How the candidates were compared

The table compares the Base16 role colours against the known Carbon palette.
It uses the mean Euclidean RGB distance by matching role to role. It is useful
for finding close palettes, but it cannot measure typography, icon quality, or
whether a background has the right emotional temperature. A lower number means
the hex values are closer.

| Theme | Mean RGB distance | What matches | What breaks the Carbon look |
| --- | ---: | --- | --- |
| [Flexoki Dark](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/flexoki-dark.yaml) | 39.1 | Neutral near-black layers and a soft light foreground | Its accents are intentionally earthy and muted. It loses the bright-colour request. |
| [Mountain](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/mountain.yaml) | 39.3 | Almost the same neutral darkness and hierarchy | Even quieter accents than Flexoki. Pleasant, but too grey for this goal. |
| [Deep Oceanic Next](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/deep-oceanic-next.yaml) | 41.5 | The closest red, orange, yellow, green, cyan, blue, purple, and pink family | Its canvas is teal `#001C1F`, not neutral black. |
| [Ayu Dark](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/ayu-dark.yaml) | 49.0 | Near-black `#0B0E14`, bright teal, green, cyan, blue, and purple | The canvas is navy, text is cream, and its yellow and orange are much hotter. |
| [OneDark Dark](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/onedark-dark.yaml) | 51.9 | Literal black, dark slate panels, and the same broad colour order | The accents are brighter and its panels lean blue-grey. |
| [Material Darker](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/material-darker.yaml) | 51.9 | The closest familiar Material-style syntax family | `#212121` is much lighter than Carbon. Its primary text is also stark white. |

All of these schemes receive the same generated Stylix target coverage because
they are in the same Tinted collection. Theme choice does not change Stylix's
per-application support. Native ports are different.

## The useful existing choices

### OneDark Dark

OneDark Dark is the closest ready-made choice for the actual feeling of a black
desktop with colourful code. It starts at literal black, then moves through
`#1C1F24` and `#2C313A`. Its red, yellow, green, cyan, blue, and purple remain
recognisable on black. The upstream palette is maintained in the Tinted
collection, and One Dark has a long-lived editor ecosystem based on Atom's
[original palette](https://github.com/atom/one-dark-syntax/blob/master/styles/colors.less).

It is still not Carbon. In particular, the accent cyan `#2BBAC5` is less soft
than Carbon teal, and the blue-grey panels make it feel more technical. Use it
as a no-custom-code trial, not as the final reference palette.

### Ayu Dark

Ayu Dark is closer to Carbon's background levels: `#0B0E14`, `#131721`, and
`#202229`. It also has a well-maintained, official VS Code extension with an
icon theme and dark, mirage, and light variants. [Ayu's VS Code source](https://github.com/ayu-theme/vscode-ayu)
documents those choices.

It has the right density but the wrong personality. Ayu's canvas is blue-black
and its warm foreground and amber details make it feel editorial. Carbon is
more neutral and less saturated.

### Deep Oceanic Next

Deep Oceanic Next is the closest numerical match for the syntax colours. Its
yellow, green, blue, purple, and pink sit very near the Carbon roles. It fails
the central visual requirement because `base00` is dark teal. Do not use it as
the system preset, but it is strong evidence that Carbon's syntax palette is
closer to an oceanic family than to Gruvbox or Catppuccin.

### Oxocarbon

[Oxocarbon Dark](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/oxocarbon-dark.yaml)
is not a colour match. Its background begins at `#161616`, its text is near
white, and its accents are more electric. It does provide the better design
idea: a consistent ramp of neutral surfaces, restrained borders, and a few
bright semantic colours. Its [style guide](https://github.com/nyoom-engineering/oxocarbon/blob/main/docs/style-guide.md)
is worth borrowing from when designing the custom theme.

## Recommendation: an original Carbon Neon theme

Make Carbon Neon the third shared `appearance.theme` choice, next to
Catppuccin Mocha and Gruvbox Dark Medium. Let its Base16 file drive Stylix.
Then add narrow native overrides for applications where Base16 cannot express
the teal UI accent cleanly.

I would retain these Carbon values:

| Role | Value | Reason |
| --- | --- | --- |
| Main canvas | `#0A0A0A` | It reads as black on an OLED but is less severe than literal black. |
| First and second surfaces | `#101213`, `#161718` | They give menus and inputs a boundary without making the desktop grey. |
| Main text | `#D9D9D9` | 14.03:1 against the main canvas. It is bright without being pure white. |
| Interaction accent | `#80CBC4` | 10.61:1 against the canvas. Use it for focus, selection, tabs, links, and primary actions. |
| Yellow, green, cyan, blue, purple, pink, orange | `#D5B05F`, `#A3C679`, `#6EBAD7`, `#6A90D0`, `#A178C4`, `#D6808F`, `#CD775C` | These preserve the calm, colourful Carbon character. |

I would make two deliberate changes.

1. Raise error red from `#C85E60` to `#D36768` in the accessible variant.
   The original red is 4.93:1 on `#0A0A0A` but only 4.47:1 on the raised
   `#161718` surface. The adjusted red is 5.57:1 and 5.05:1 respectively. It
   still reads as the same muted coral.
2. Treat `#383838` as a decorative separator, not a required control boundary.
   It has only 1.69:1 contrast on the canvas. Use `#5E6066` for any border,
   icon, or outline that must identify a control, since it reaches 3.15:1.
   Keep `#7A7A80` for readable comments and secondary labels at 4.64:1.

Those changes follow the contrast floors in [WCAG's text criterion](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
and [non-text criterion](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).

## The Base16 trade-off that needs a decision

Base16 gives eight accent slots. Carbon wants eight syntax colours *plus* teal
as a separate UI colour. A single Base16 file cannot encode all nine.

The better system default is to map `base0D` to teal `#80CBC4`. Stylix targets
often use this role for links, focus, and selected controls. In VS Code, set
the function and symbol colour back to Carbon blue `#6A90D0` with a scoped
token rule. This gives the desktop its teal identity without giving up the blue
in the editor.

The stricter alternative maps `base0D` to Carbon blue and applies teal through
each native app configuration. That preserves every syntax mapping but creates
more code and misses generic Stylix targets. I would not choose it.

## Native application policy

Use the generated Carbon Neon palette for Firefox Color, Zen, GTK, Qt,
terminals, Rofi, Waybar, and other Stylix targets. Do not leave a forced
Catppuccin or Gruvbox browser theme enabled when Carbon Neon is active. A
generated neutral-black browser is more coherent than a high-quality but
mismatched branded theme.

For VS Code, use an open, maintained syntax theme that accepts token overrides
or a small in-repository workbench theme. Ayu is the best existing base for
that route because its official extension also provides matching icons. Do not
make the proprietary Vira package part of the system configuration.

For Spotify and Chromium-family browsers, prefer a generated or lightweight
custom palette over a forced native theme from a different colour family.
There is no quality native port that makes the exact Carbon palette a better
choice than generated theming.

## Decision

If you want a ready-made option today, try OneDark Dark first. If you want the
theme you described, build Carbon Neon with the two accessibility adjustments
above. It will look more intentional than forcing Catppuccin, Gruvbox, or Ayu
to impersonate Vira Carbon.
