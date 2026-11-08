# OLED-friendly high-contrast themes

## Recommendation

Use **Black Metal (Mayhem)** when the priority is a genuinely black desktop
with strong, comfortable text contrast. Its Tinted Base16 palette has a true
black `base00` (`#000000`), grey primary text (`#c1c1c1`), yellow syntax
(`base0A`, `#eecc6c`), and cream syntax (`base0B`, `#f3ecd4`). It is present
in the exact Tinted schemes revision pinned by this flake, so Stylix can use it
directly:

```nix
inputs.stylix.inputs.tinted-schemes + "/base16/black-metal-mayhem.yaml"
```

The primary text pair is **11.67:1**. That clears WCAG 2.2's 7:1 enhanced
contrast threshold for normal text. OLED pixels that display `#000000` emit no
light, so this is the only recommendation here that gives a true-black canvas.
See the [Black Metal Mayhem palette](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/black-metal-mayhem.yaml), the [OLED technical explanation](https://h20195.www2.hp.com/v2/GetDocument.aspx?docname=4AA7-8109ENW), and [WCAG 2.2 contrast requirements](https://www.w3.org/TR/wcag/).

This is my pick over a pure white-on-black theme. `#c1c1c1` is still very
readable, but it avoids making every paragraph look like a bright white light
source. The Mayhem accents retain a little character instead of reducing the
desktop to monochrome grey.

## Palette comparison

The contrast values below use WCAG's relative-luminance formula on `base05`
over `base00`. They describe the standard text pair only. Individual widgets
and syntax roles can use other pairs, so they still need a visual check after
application.

| Scheme | Background | Primary text | Contrast | OLED-black? | Verdict |
| --- | --- | --- | ---: | --- | --- |
| [Black Metal Mayhem](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/black-metal-mayhem.yaml) | `#000000` | `#c1c1c1` | 11.67:1 | Yes | Best balanced true-black choice. Its yellow and cream accents reach 13.49:1 and 17.76:1. |
| [Da One Black](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/da-one-black.yaml) | `#000000` | `#ffffff` | 21.00:1 | Yes | Maximum measured contrast. Choose it only if the deliberately stark white-on-black look is the goal. |
| [IR Black](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/irblack.yaml) | `#000000` | `#b5b3aa` | 9.99:1 | Yes | Warmer alternative, but less visually cohesive than Mayhem's restrained grey ramp. |
| [Gruvbox dark hard](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/gruvbox-dark-hard.yaml) | `#1d2021` | `#d5c4a1` | 9.56:1 | No | Excellent warm, high-contrast theme. It is near-black, not OLED black. |
| [Catppuccin Mocha](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/catppuccin-mocha.yaml) | `#1e1e2e` | `#cdd6f4` | 11.34:1 | No | Strong contrast and the best native-port ecosystem, but it has a purple near-black background. |
| [Tokyo Night Storm](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/tokyo-night-storm.yaml) | `#24283b` | `#a9b1d6` | 6.90:1 | No | Polished, but its primary text pair falls just below the 7:1 enhanced target. |

The Black Metal variants share the same black background and primary text.
They differ only in the accent colours. [Bathory](https://raw.githubusercontent.com/tinted-theming/schemes/9bd28ed313560db3c5b605c63bc4e309e78e3fc8/base16/black-metal-bathory.yaml)
is the warmer alternative if Mayhem's yellow feels too bright.

## Support trade-off

Stylix can render any of these Tinted Base16 files into the same enabled
targets. The Tinted project publishes the scheme collection and template
catalogue itself. [Its project documentation](https://github.com/tinted-theming/home)
lists maintained builders and target templates.

The current configuration's native integrations are intentionally tailored to
Catppuccin Mocha and Gruvbox Dark Medium. Black Metal Mayhem has no comparable
maintained, first-party native theme family for the browser UI, VS Code,
Spotify, and every other non-Stylix application. It will look coherent across
Stylix targets, but adopting it across the whole configuration would require
purposeful per-application fallbacks or custom palettes. Do not leave a
Catppuccin or Gruvbox native extension active while the system palette is Black
Metal.

If whole-config native support matters more than literal black, keep
Catppuccin Mocha. If literal black is the non-negotiable requirement, use
Black Metal Mayhem and add native integrations only after checking that each
one has a maintained source.
