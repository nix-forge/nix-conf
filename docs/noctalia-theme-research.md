# Consistent Noctalia colors across custom themes

Reviewed: 2026-09-09. Scope: Noctalia 5.0.0, revision
`f96a407deb109c9db6f29db75e6fe487a5289e02`, and the repository's Stylix target.

## Answer

Keep Stylix as the palette owner and use Noctalia's semantic color roles across
the shell. Check the colors Noctalia actually renders, including hover and
variant surfaces. A valid Base16 palette does not guarantee readable small text
on every shell background. Preserve the theme's accent hues while choosing
foregrounds and secondary text by contrast. The four supported schemes are dark;
keep dark mode explicit. A future light scheme needs its own palette instead of
Noctalia's dark-palette fallback.

Use Apple's consistency principles through the existing theme: restrained
selection accents, readable neutral labels, coherent corner sizes, and clear
grouping. These principles do not require Apple logos, Apple colors, or
translucent backgrounds. [Apple color guidance](https://developer.apple.com/design/human-interface-guidelines/color?changes=_2_2)

## Findings and sources

### Semantic roles are the integration boundary

Noctalia's palette supplies bars, panels, widgets, and other themed UI. Its
documentation recommends role names in configuration so colors follow the
selected palette. `primary` identifies actions and selection; `on_primary`
belongs on primary fills. `on_surface` and `on_surface_variant` identify primary
and secondary content. `error` identifies errors and destructive actions.
Keep fixed hexadecimal colors out of widget overrides unless the color has a
separate meaning, such as an application's own artwork.
[Noctalia palette roles](https://docs.noctalia.dev/noctalia/theming/palette/)

Apple recommends consistent meanings for colors, separate light and dark
variants, and alternatives to hue alone when conveying state. It specifically
discourages borrowing a separator color for text. Applying those principles
here means fixing unreadable secondary labels in the shared palette instead
of giving individual widgets unrelated colors.
[Apple color guidance](https://developer.apple.com/design/human-interface-guidelines/color?changes=_2_2)

### Source behavior differs from the apparent JSON contract

The pinned source has several behaviors that matter when reviewing the
[palette renderer](../modules/shared/stylix/targets/noctalia/palette.nix):

| Input or operation | Pinned behavior | Consequence |
| --- | --- | --- |
| Missing `light` | Copies the entire `dark` variant into light mode. The `dark` object and complete terminal colors are required. | A light-mode toggle does not manufacture a light palette. |
| Core accent and text pairs | Fixed-palette expansion preserves supplied values. | Validate all supplied `on_*` pairs; there is no general automatic repair. |
| `mHover` and `mOnHover` | Parsed, but expansion does not retain them. The UI mapping uses tertiary and on-tertiary instead. | Changing these JSON fields alone does not change rendered hover colors. |
| `mOutline` | Expansion corrects an intermediate outline to 3:1 against the main surface, then derives a subtler outline variant. The UI receives that variant. | The intermediate 3:1 correction does not prove the shell outline meets 3:1. |
| Derived containers | Expansion computes additional surface levels and contrast-adjusts generated accent-container text. | Test text on the expanded backgrounds, especially elevated cards. |

These are source observations, not assumptions from the documentation.
[Palette loading](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/theme/theme_service.cpp#L162),
[fixed-palette expansion and UI mapping](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/theme/fixed_palette.cpp#L245).
The documentation still lists independent hover roles, so retain this discrepancy
when assessing a future upstream update.
[Documented hover roles](https://docs.noctalia.dev/noctalia/theming/palette/#color-roles)

The distinction affects ordinary controls. Default buttons use primary text on
a variant background, and all ordinary button variants use hover/on-hover for
their hover state. Checking only `mOnSurface` against `mSurface` misses both
cases. [Button state colors](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/ui/controls/button.cpp#L32)

### Use measurable contrast without making every border prominent

Use WCAG 2.2 as a design benchmark: ordinary text needs at least 4.5:1 against
its background. Large text can use 3:1, but small bar labels do not qualify.
Secondary, placeholder, and hovered text still need readable contrast.
An unselected but clickable workspace is not a disabled control. Compute
ratios from the configured foreground/background colors without rounding a
failing result upward. [WCAG text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)

Meaningful control or state indicators need 3:1 against adjacent colors.
Decorative card borders and optional hover fills do not automatically need
that ratio when contrasting labels or icons already identify the control.
Keyboard focus and selection indicators still need to remain visible.
This permits quiet surfaces without sacrificing essential information.
[WCAG non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)

### Dark mode, transparency, and accessibility need separate checks

Noctalia applies pure-black and high-contrast transformations to custom
palettes after loading them. Pure-black lowers the dark surface ramp in HCT
tone while preserving terminal selection backgrounds. High contrast shifts
tones on either side of 50 and forces brighter or darker outlines. It does
not evaluate each resulting foreground/background pair against a contrast
threshold. Keep it available as an accessibility setting, but do not use it
as proof that the normal palette is readable.
[Palette transformations](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/theme/palette_transform.cpp#L42),
[transformation ordering](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/theme/theme_service.cpp#L505).

Inference: solid panels make contrast predictable across changing wallpaper.
Keep the [shared visual baseline](../modules/shared/stylix/targets/noctalia/settings.nix)
responsible for panel material, typography, borders, and corner scaling. Use
the native size hierarchy for buttons, cards, and popovers; identical radii
on very different sizes do not produce consistent proportions.

## Validation and limits

The palette check builds all four schemes through the production renderer and
independently measures 17 text pairs per scheme. It also checks scrollbar
contrast, unchanged surfaces and terminal colors, and preservation of colors
that already pass. The generation target is 4.75:1, with 4.5:1 as the test's text
minimum. This margin allows modest rounding differences. These are configured
color measurements, not a claim about every antialiased pixel.

| Scheme | Original minimum text ratio | Prepared minimum text ratio |
| --- | --- | --- |
| Carbon Neon | 4.40:1 | 4.78:1 |
| Carbon Neon OLED | 4.40:1 | 4.78:1 |
| Catppuccin Mocha | 2.46:1 | 4.81:1 |
| Gruvbox Dark Medium | 3.37:1 | 4.76:1 |

The pinned shell's native `theme --theme-json` expansion was also checked for
all four schemes, including OLED transformation. It retained passing core UI
pairs. Home Manager checks cover target opt-outs and opaque popup settings.
The UI mapping uses `surface` and `surface_container`; additional generated
container tokens are not interchangeable with these runtime palette fields.

Live inspection exposed additional opacity reductions in placeholders and
calendar labels. The personal Noctalia variant now uses the supplied semantic
text colors directly in those states. Slider handle borders use secondary text,
and scrollbar thumbs use that role at 85% opacity; the palette check verifies
the composited scrollbar color reaches 3:1 against both UI surfaces. Disabled
controls retain their existing treatment. The patch is in the
[owning package](../pkgs/pkgs/by-name/no/noctalia-personal/README.md).
Compare upstream [input colors](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/ui/controls/input.cpp#L1600)
and [calendar labels](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/ui/controls/calendar_view.cpp#L283).

Live Linux inspection covers the current dark theme's bar, launcher, Control
Center, session panel, notification, and volume OSD. Other schemes are covered
by generated-color checks, not a complete interactive review. No light scheme
is currently offered. This work is not a full accessibility conformance audit.
Raw screenshots and environment captures remain outside public documentation.

The personal shell built successfully on x86_64 Linux and was applied to the
running session. Package independence, package unit tests, and package lint
passed. The lint check used a snapshot without Git administrative files because
a raw `path:` copy of a submodule retains a Git pointer that is invalid inside
the Nix sandbox.

A whole-image workspace timing check did not converge and is inconclusive.
A follow-up check of the active selection's accent pixels measured four
workspace changes at 142–199 ms. This confirms prompt highlight updates in
that check; it does not establish an icon-update latency bound.

## Implication for this repository

### Typography and icon sizing

The shared target uses `stylix.fonts.sansSerif.name` for both shell and bar text.
Noctalia's desktop surfaces, including its settings window, use a body-text scale
derived from `stylix.fonts.sizes.desktop`. Stylix point sizes convert to logical
pixels at 4/3; Noctalia's native body size is 14 pixels. The bar has its own font
scale and does not inherit the accessibility UI scale, so both receive the same
derived ratio. Native captions and headings retain their size hierarchy.

Notification and OSD scales multiply the shell scale. Their local multiplier is
therefore `sizes.popups / sizes.desktop`, avoiding double scaling. Contract tests
check a different font family, 12-point desktop text producing a 16-pixel body
baseline, and 15-point popup text producing a 20-pixel baseline.

Bar glyphs and workspace application icons use 16-pixel logical boxes, with
full-opacity application artwork. Tray foregrounds use `on_surface`. Known
static tray bitmaps have explicit theme-icon mappings, including Zoom's video
camera. Attention icons and overlays retain their state information.

The personal package selects vector status artwork at its logical display size,
then rasterizes it at the output resolution. Selecting a larger padded status
asset and shrinking it made some icons look disproportionately small. Bitmap
and ordinary app artwork retain high-resolution lookup. The icon-policy tests
cover logical-size selection, scaled size requests, missing icons, and preservation
of bitmap and application-artwork resolution.

The typography/icon update passed the Linux package build, icon-policy tests,
package lint and independence checks, and the Home Manager typography contracts.
Rasterizing the installed Papirus ChatGPT status assets into a 16-pixel box
measured a 10-by-10 opaque extent for the 24-pixel variant and 16-by-16 for the
16-pixel variant. The new build and generated configuration were applied to the
running shell. Its final screenshot check remains pending: Hyprlock activated
during the build and the compositor returned obscured captures.

### Ownership

Keep palette adaptation in the existing Stylix target and preserve the desktop's
centered workspace groups, regular application artwork, and disabled active-app
dots. Repair low-contrast semantic pairs at that shared boundary. Keep neutral
surfaces subdued, use accent color for selection and interaction, and test light
mode when introducing a light scheme, using explicit palette generation and matching mode selection. Any
source-level repair belongs to the Noctalia package repository and needs its
own validation and override review.
