# A black, colourful theme informed by Vira Carbon

## Recommendation

Build an original **Carbon Neon** palette for Stylix. Use Vira Carbon as a
visual reference, not as source material. It is the closest match to the
requested direction: an almost-black neutral canvas, soft grey body text, one
teal interaction accent, and readable colour for syntax and status.

Use it as the system source of truth. Let Stylix cover the desktop, GTK, Qt,
terminal, Firefox Color, Zen, Rofi, Waybar, and other Base16 targets. Keep
Vira Carbon itself as an optional VS Code-only choice if its commercial licence
is already desired. Do not try to redistribute its theme or icons through this
Nix configuration.

There is one important catch. A Base16 theme has eight semantic accent slots,
whereas Vira Carbon uses separate teal, cyan, blue, purple, pink, red, orange,
yellow, and green roles. A custom Base16 version can preserve the character,
but not every separate Vira colour. Reserve teal for interactive UI and use
cyan for the Base16 cyan slot, or make teal the cyan slot and keep the syntax
palette deliberately tighter. Trying to make all applications mimic every VS
Code detail will make the configuration fragile.

## What Vira Carbon actually does

Vira's official Marketplace entry calls it a commercial product. Its published
VSIX package is version `2026.8.0` at the time of this research and directs
licensing to Vira's terms. The package exposes Vira Carbon and Vira Carbon High
Contrast as separate themes. The public support repository is for support, not
the theme source. [Marketplace entry](https://marketplace.visualstudio.com/items?itemName=vira.vsc-vira-theme), [official VSIX package](https://marketplace.visualstudio.com/_apis/public/gallery/publishers/vira/vsextensions/vsc-vira-theme/latest/vspackage), [terms](https://vira.build/terms-conditions).

The palette below is a short factual description of the compiled Carbon theme,
inspected from that official VSIX. It is enough to explain the look. It is not
a replacement for the extension's assets or implementation.

| Role | Carbon value | How it is used |
| --- | --- | --- |
| Main canvas | `#0A0A0A` | Editor, sidebar, panels, title bar, tabs |
| Raised surface | `#161718` | Inputs, request bubbles, peek views |
| Main text | `#D9D9D9` | Body text and active UI labels |
| Muted text | `#56575D` | Inactive labels and breadcrumbs |
| Divider | `#383838` | Indent guides and structure |
| UI accent | `#80CBC4` | Focus, active tab, links, selection, buttons, badges |
| Cursor | `#FFCC00` | Cursor and bracket match |
| Syntax/status colours | `#C85E60`, `#D5B05F`, `#A3C679`, `#6EBAD7`, `#6A90D0`, `#A178C4`, `#D6808F`, `#CD775C` | Red, yellow, green, cyan, blue, purple, pink, orange |

The High Contrast variant keeps the accent and syntax colours. Its meaningful
change is hierarchy: its editor and popup surfaces move from `#0A0A0A` to
`#101213`, while frame borders become more visible. That is a useful lesson.
Black screens still need a small, consistent surface ramp to show where things
begin and end.

Vira also exposes a global accent setting for its UI and icons, including a
custom six-digit hex value. Its built-in choices include teal `#80CBC4`, bright
teal `#64FFDA`, cyan `#57D7FF`, blue `#5393FF`, indigo `#758AFF`, purple
`#B54DFF`, pink `#FF669E`, lime `#39EA5F`, yellow `#FFCF3D`, and orange
`#FF7042`. This makes it likely that "Carbon accent" meant the Carbon variant
with one selected accent. Carbon defaults to teal in the published theme.
[Vira customisation documentation](https://vira.featurebase.app/en/help/articles/6975827-customisation).

## Contrast and colour rules worth keeping

WCAG gives useful floors even for a personal desktop. They are not a complete
measure of taste or eye comfort, but they catch the bad failures.

- Body text should clear 4.5:1 against its actual surface. 7:1 is the enhanced
  target for text. The primary Carbon pair, `#D9D9D9` on `#0A0A0A`, is 14.03:1.
  [WCAG text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), [enhanced contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-enhanced.html).
- A focus ring, active-tab stripe, checkbox tick, or other meaningful UI cue
  needs at least 3:1 against adjacent colours. Carbon teal reaches 10.61:1
  against the main canvas, so it is an excellent interaction accent. Thin
  borders should exceed the minimum because anti-aliasing reduces their visible
  contrast. [WCAG non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).
- Hue alone must not carry meaning. Use red plus an error icon or text, green
  plus a success mark, and a focus ring in addition to a colour change. This
  matters in terminals, diffs, notifications, and Git indicators. [WCAG use of
  color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html).
- Avoid saturated red as the only small text colour on black. WCAG's rationale
  specifically calls out the reduced usefulness of long-wavelength red on a
  dark background for some people with protanopia. Carbon's softened red
  `#C85E60` is 4.93:1, adequate for short semantic text but still better used
  for errors and diffs than paragraphs. [WCAG contrast rationale](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html#rationale-for-the-ratios-chosen).

These are the Carbon values measured against `#0A0A0A` with WCAG relative
luminance. They explain why the theme feels colourful without becoming a neon
wall.

| Colour | Contrast | Best role |
| --- | ---: | --- |
| `#80CBC4` teal | 10.61:1 | Focus, links, selected state, primary action |
| `#D5B05F` yellow | 9.62:1 | Warnings, types, cursor, attention |
| `#A3C679` green | 10.29:1 | Success, additions, strings |
| `#6EBAD7` cyan | 9.11:1 | Keywords and punctuation |
| `#6A90D0` blue | 6.14:1 | Functions, informational states |
| `#A178C4` purple | 5.66:1 | Storage, modifiers, optional secondary accent |
| `#D6808F` pink | 6.92:1 | Constants and boolean values |
| `#CD775C` orange | 6.02:1 | Numbers and secondary keywords |
| `#56575D` muted grey | 2.75:1 | Inactive or decorative UI only |
| `#45454A` comment grey | 2.08:1 | Deliberately subdued comments only |

The two low-contrast greys are part of Vira's hierarchy, but they are too dim
for text that needs to be read reliably. For the custom system palette, use
`#7A7A80` for readable comments and secondary labels. It reaches 4.64:1 against
`#0A0A0A`. Keep `#45454A` and `#56575D` for dividers, inactive glyphs, and
other low-priority decoration.

## Proposed original Carbon Neon palette

This is a design proposal, not a copy of a packaged Vira theme. It uses the
same broad idea while giving the shared Stylix palette clear semantic roles.

| Base16 role | Proposed value | Purpose |
| --- | --- | --- |
| `base00` | `#0A0A0A` | Main background. Near-black rather than literal black. |
| `base01` | `#101213` | Sidebar and popup surface. |
| `base02` | `#161718` | Inputs and raised panels. |
| `base03` | `#383838` | Dividers and inactive structure. |
| `base04` | `#7A7A80` | Readable comments and secondary text. |
| `base05` | `#D9D9D9` | Main text. |
| `base06` | `#F4F4F4` | Strong text. |
| `base07` | `#FFFFFF` | Rare maximum emphasis. |
| `base08` | `#C85E60` | Error and deletion. |
| `base09` | `#CD775C` | Numbers and constants. |
| `base0A` | `#D5B05F` | Warning and type. |
| `base0B` | `#A3C679` | Success and string. |
| `base0C` | `#6EBAD7` | Keyword and punctuation. |
| `base0D` | `#6A90D0` | Function and link. |
| `base0E` | `#A178C4` | Modifier and class. |
| `base0F` | `#D6808F` | Special values. |

Set `#80CBC4` separately as the common UI accent in app-level configuration.
This avoids misusing an ANSI syntax slot and gives focus, selection, tabs,
buttons, and hyperlinks one recognisable colour. If a target only accepts
Base16, use `base0C` as its interaction colour, accepting that it will be the
slightly cooler cyan rather than Carbon teal.

For a literal OLED-black edition, change only `base00` to `#000000` and leave
the surfaces at `#0A0A0A`, `#101213`, and `#161718`. That preserves hierarchy.
It will look more stark than Vira Carbon, whose editor background is near black
rather than pure black.

## Existing foundations compared

| Candidate | Visual match | Native support | Decision |
| --- | --- | --- | --- |
| Custom Carbon Neon | Exact intent | Stylix targets work well. Native non-Stylix apps need explicit, per-app configuration. | Best system palette if visual coherence matters most. |
| Ayu Dark | Very close. Its official Base16 background is `#0B0E14`, with bright orange, yellow, green, cyan, blue, and purple. | Official VS Code theme and icons. Fewer maintained ports than Catppuccin or Dracula. | Best ready-made option to try before writing a custom scheme. [Tinted scheme](https://github.com/tinted-theming/schemes/blob/spec-0.11/base16/ayu-dark.yaml), [Ayu VS Code port](https://github.com/ayu-theme/vscode-ayu). |
| Catppuccin Mocha with dark overrides | Good colour family, but its stock canvas is purple-tinted `#1E1E2E`, not Carbon black. | Strongest existing support in this configuration and unusually good declarative VS Code customisation. | Best hybrid if native ports matter more than exact system-wide colour matching. |
| Dracula | Bright syntax colours and a mature application catalogue, but `#282A36` is visibly navy-grey. | Broad community support and a documented palette. | Good alternate, not the requested black Carbon look. [Dracula palette and support](https://github.com/dracula/dracula-theme). |
| Black Metal Mayhem | True black, but almost monochrome. | Stylix coverage only in practice. | Reject for this goal. It loses the bright multi-hue character. |

Catppuccin deserves a special note. Its official VS Code port supports
declarative Nix builds, palette overrides, a custom accent, and a documented
"OLEDppuccin" example that sets Mocha's base, mantle, and crust to black. That
makes it a sound way to keep Catppuccin's icons and extension integrations in
VS Code while experimenting with a black workbench. It cannot make every
independent Catppuccin port use the same custom palette, so it is not a
complete Carbon Neon system theme. [Catppuccin VS Code configuration](https://github.com/catppuccin/vscode#nix-home-manager-users).

## Recommended decision path

1. Try Ayu Dark for a week. It is already in the Tinted collection and is the
   closest high-quality, maintained preset to this direction.
2. If its blue-black background and amber are close but not right, add the
   original Carbon Neon Base16 file and make it a third `appearance.theme`
   choice. Keep the palette as a small in-repo source file with tests for text
   and focus contrast.
3. Configure VS Code separately. Either use Vira Carbon under its licence, or
   use Catppuccin's supported palette overrides as an adjacent, not identical,
   theme. Do not embed or rebuild Vira's proprietary assets.
4. Use browser and Spotify fallbacks generated from the Carbon Neon palette
   instead of leaving a Catppuccin or Gruvbox browser theme enabled. A coherent
   generated palette looks better than a well-made but mismatched native port.

The one user choice still worth confirming before implementation is which Vira
accent was selected with Carbon. The standard Carbon theme uses teal. If the
remembered accent was cyan, blue, purple, or pink, that colour should become
the single UI-accent token rather than teal.
