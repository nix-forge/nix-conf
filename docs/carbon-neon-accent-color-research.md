# Carbon Neon: choosing a primary accent

## Decision

**Keep teal (`#80CBC4`) as Carbon Neon's primary interaction accent.** This
is not a default-by-inertia decision. On a near-black OLED canvas, it offers a
rarely good balance of: very high measured contrast (10.61:1 against
`#0A0A0A`), enough visual distinction for a thin focus/tab marker, and less
visual heat than the brighter cyan, lime, or amber candidates. It also leaves
green, amber/orange, and red available for success, warning, and error states.

Use it only for *interactive emphasis* (keyboard focus, current selection,
primary action, and links). Do **not** use it for every icon, status item, or
background. The earlier bright quota-status issue was a role-allocation
problem, not evidence that teal is a bad accent.

There is no first-party accessibility standard that identifies one objectively
best hue. The recommendation below is an explicit design inference from
contrast, semantic separation, Vira's published choices, and the stated goal:
bright colour on a mostly black screen, while the editor—not the chrome—keeps
attention.

## Evidence and constraints

- VS Code gives separate tokens for focus, active-tab borders, selection and
  semantic warning/error status items. Its own token model therefore supports
  a single interaction accent *alongside*, rather than in place of, semantic
  state colours. [VS Code theme-color reference](https://code.visualstudio.com/api/references/theme-color)
- VS Code explicitly says `statusBarItem.prominent*` is for an item that must
  stand out. A quota indicator styled through that role should be quiet unless
  it needs immediate attention. Accent hue cannot correct misuse of an
  attention-level token. [VS Code status-bar tokens](https://code.visualstudio.com/api/references/theme-color#status-bar-colors)
- W3C requires 4.5:1 for normal-size text and 3:1 for non-text controls. It
  also says hue is not a sufficient carrier of meaning. Contrast is therefore
  a floor, not a reason to use the brightest available colour everywhere.
  [Contrast Minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum),
  [Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast),
  [Use of Color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color)
- Apple's dark-mode guidance independently supports a shallow base/elevated
  surface hierarchy, strong small-text contrast, and controlled use of colour
  on dark interfaces. Its current color guidance says to apply colour
  sparingly and reserve it for primary actions or meaningful status. [Dark
  Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode),
  [Color](https://developer.apple.com/design/human-interface-guidelines/color)
- Fluent likewise separates neutral, brand, and status tokens; it recommends
  using shared colour sparingly to highlight important UI. [Fluent 2 color
  tokens](https://fluent2.microsoft.design/color-tokens/), [Fluent 2
  color guidance](https://fluent2.microsoft.design/color/)
- Vira is a commercial, closed theme. Its first-party documentation confirms
  that UI and icon accents are configurable, including a custom hex value, but
  its terms prohibit extracting or replicating the product. This assessment
  therefore uses Vira as an interaction-model reference, not copied package
  internals. [Vira customisation guide](https://vira.featurebase.app/en/help/articles/6975827-customisation),
  [Vira terms](https://www.vira.build/terms-conditions), [Vira Marketplace
  listing](https://marketplace.visualstudio.com/items?itemName=vira.vsc-vira-theme)

## Candidate comparison

The contrast figures are WCAG relative-luminance calculations against Carbon
Neon's `#0A0A0A` canvas. They measure visibility, **not** comfort or visual
priority. The samples are Carbon's existing palette values or proposed
independent alternatives; they are not claimed to be copied Vira tokens.

| Candidate | Sample | Contrast | Assessment as the one UI accent |
| --- | --- | ---: | --- |
| **Teal** | `#80CBC4` | **10.61:1** | **Best overall.** Clearly visible without making the interface read as blue, warning-yellow, or success-green. It is sufficiently bright for narrow focus geometry without requiring coloured fills. |
| Cyan | `#6EBAD7` | 9.11:1 | **Rank 2.** Good if a colder, more technical/neon look is preferred. A brighter cyan such as `#57D7FF` reaches 11.85:1, but is more likely to repeat the unwanted attention pull of the bright blue status item. |
| Violet | `#A178C4` | 5.66:1 | **Rank 3.** The strongest non-blue alternative: colourful, distinctive, and still clear on black. It has less contrast headroom and competes with Carbon's modifier/class syntax colour, so focus must also use a border/shape. |
| Blue | `#5393FF` | 6.59:1 | Viable but not preferred. It is the closest visual family to the distracting quota block in the screenshots and is already a useful informational/function hue. A muted blue can be an *info* colour rather than the desktop's default action colour. |
| Magenta/pink | `#FF669E` | 7.21:1 | Expressive and legible, but it competes with string/constant syntax and will make a whole desktop feel more decorative. A good opt-in personality variant, not the balanced default. |
| Lime/chartreuse | `#39EA5F` | 12.36:1 | Very visible, but it naturally collides with success/playing/available states—the same reason Spotify's original green hover looked wrong in Carbon. Keep it semantic. |
| Amber | `#FFCF3D` | 13.43:1 | Highest contrast here, which is exactly why it is better reserved for warnings, cursor/bracket matching, and exceptional attention. Not a calm persistent accent. |
| Orange | `#FF7042` | 7.21:1 | Adequate contrast but overlaps warning/attention semantics and is visually warmer than the requested Carbon reference. Better as a secondary syntax/status colour. |

Vira's documented accent picker and custom-hex support confirm the visual
family allows several valid personal choices, not that any one is universally
superior.
[Vira customisation guide](https://vira.featurebase.app/en/help/articles/6975827-customisation)

## Recommended hierarchy

1. **Default — Carbon Teal `#80CBC4`**: focus rings, selected checkboxes,
   active-tab stripe, text links, and the single primary action in a view.
2. **Alternative — Carbon Cyan `#6EBAD7`**: choose this only if you want a
   colder/more neon character. Keep it out of persistent status-bar fills.
3. **Alternative — Carbon Violet `#A178C4`**: choose this for a more creative,
   less conventional feel. Pair it with a clear focus outline because it has
   lower luminance contrast than teal or cyan.

Regardless of the selected accent, maintain these separate semantic roles:

- red/coral for errors and removals;
- amber/orange for warnings and attention;
- lime/green for success, additions, and playing/available state;
- blue for information or function syntax;
- neutral greys for inactive chrome and ordinary status content.

The accent choice should be a single declarative token used consistently by
Stylix-adjacent configurations. Where a target cannot accept a separate UI
accent, use its focus/link slot—not an error, success, or warning slot.

## Uncertainties and a safe next step

Display calibration, ambient light, motion/hover behaviour, and the user's
colour preference materially change perceived intensity. OLED black increases
the perceived contrast of any bright saturated element; it does not make one
hue intrinsically healthier. The calculated values also do not predict colour
vision differences, which is why focus and status must retain non-colour cues.

No configuration was changed as part of this research. If an implementation is
wanted, the least risky approach is to add a named `carbonNeonAccent` selector
with the three values above, retain semantic colours, and apply the choice only
to interaction tokens—not to passive workbench chrome.
