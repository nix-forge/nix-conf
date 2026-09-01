# VS Code Diff Theme Research

## Scope

This note evaluates the green and red backgrounds in Carbon Neon's VS Code
diff view. The goal is a reviewable, calm diff on a near-black editor: changed
text should be easy to find, while broad changed-line fills should not tint the
whole editor olive or crimson.

## Why the current colours feel wrong

Carbon Neon currently does not specify any `diffEditor.*` colours, so VS Code
falls back to its registered dark diff defaults. In the current VS Code build,
those defaults are:

| Role | Resolved default | Appearance over Carbon's `#0A0A0A` editor |
| --- | --- | --- |
| Added line | `#9BB95533` | about `#272D19` — an olive, yellow-green wash |
| Added changed text | `#9CCC2C33` | about `#273111` — a more saturated yellow-green block |
| Removed line/text | `#FF000033` | about `#3C0808` — a pure, harsh red wash |

`33` is about 20% alpha. The opacity is sensible, but the fallback hues are
not part of Carbon's palette: the added colour trends yellow/olive and the
removed colour is pure red. That directly matches the screenshot.

Dark Modern deliberately does not replace those `diffEditor.*` values: it
inherits Dark+ and Dark (Visual Studio), while providing only its own green and
red gutter markers (`#2EA043` and `#F85149`). It therefore demonstrates the
use of translucent diff layers, but is not a suitable hue source for Carbon.

Sources: [Dark Modern](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/dark_modern.json), [Dark+](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/dark_plus.json), [Dark (Visual Studio)](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/dark_vs.json), and VS Code's installed default colour registry.

## What VS Code expects from a diff theme

VS Code has separate tokens for whole changed lines, changed text spans, their
gutter, and the overview ruler. Its theme reference requires inserted/removed
line and text backgrounds to be non-opaque so existing editor decorations stay
visible. It also explicitly says to use a text *background* or a text *border*,
not both.

The resulting hierarchy should be:

1. A low-alpha line overlay gives location and scope.
2. A slightly stronger text-span overlay identifies the exact edit.
3. A narrow, more opaque gutter/overview marker supports navigation without
   making the code surface busier.
4. The split divider stays neutral; it must not imply an addition or removal.

Source: [VS Code theme colour reference — Diff editor colours](https://code.visualstudio.com/api/references/theme-color#diff-editor-colors).

Catppuccin's maintained VS Code theme follows this pattern: it uses 15% alpha
for added/removed lines, 20% for changed text, and stronger overview markers.
Its green and red are palette hues rather than the editor's generic fallback
colours. That is the right structural model for Carbon Neon.

Source: [Catppuccin VS Code UI colour definitions](https://github.com/catppuccin/vscode/blob/main/packages/catppuccin-vsc/src/theme/uiColors.ts#L151-L158).

## Recommended Carbon Neon direction

Keep red/green semantic direction, but use a clean spring green for additions
and a muted rose-coral for removals. This avoids both the default olive cast
and pure-red alarm appearance, while remaining distinguishable from Carbon's
cyan focus accent.

Recommended source hues:

| Meaning | Hue | Reason |
| --- | --- | --- |
| Addition | `#78C86F` | A green-forward spring hue; recognisably positive without either the blue cast of mint or the yellow cast of Carbon's `#A3C679` string colour. |
| Removal | `#D98086` | A softened rose-coral; distinct from an error red while remaining clearly a removal. |
| Neutral diff divider | `#242526` | Matches the quiet Carbon hierarchy and keeps the split boundary unobtrusive. |

Applied token set:

```json
{
  "diffEditor.insertedLineBackground": "#78C86F26",
  "diffEditor.insertedTextBackground": "#78C86F33",
  "diffEditor.removedLineBackground": "#D9808626",
  "diffEditor.removedTextBackground": "#D9808633",

  "diffEditorGutter.insertedLineBackground": "#78C86F99",
  "diffEditorGutter.removedLineBackground": "#D9808699",
  "diffEditorOverview.insertedForeground": "#78C86FCC",
  "diffEditorOverview.removedForeground": "#D98086CC",

  "diffEditor.border": "#242526",
  "diffEditor.diagonalFill": "#161718"
}
```

The `26` line fill is 15% opacity and the `33` span fill is 20%. On a
near-black editor these yield dark, cool green/rose surfaces, with exact edited
characters a modest step stronger than the rest of the line. This preserves
syntax readability and prevents a large diff from becoming one bright field.

Do **not** set `diffEditor.insertedTextBorder` or
`diffEditor.removedTextBorder` alongside these text backgrounds; VS Code
advises against combining the two treatments.

For consistency beyond the diff editor, the implementation should also give
the standard editor's narrow source-control markers matching hues:

```json
{
  "editorGutter.addedBackground": "#78C86F99",
  "editorGutter.deletedBackground": "#D9808699",
  "editorOverviewRuler.addedForeground": "#78C86FCC",
  "editorOverviewRuler.deletedForeground": "#D98086CC",
  "minimapGutter.addedBackground": "#78C86F99",
  "minimapGutter.deletedBackground": "#D9808699"
}
```

These are thin navigational signals, so their higher alpha does not create the
same visual weight as a full-line fill. The OLED variant should use exactly the
same overlays: alpha blending against its pure-black editor makes them a touch
darker without changing their semantic relationship.

## Verification criteria after implementation

1. In an inline and a side-by-side diff, the entire changed line is visible
   without overwhelming the text.
2. Exact changed characters remain easier to identify than the surrounding
   changed line.
3. Added and removed regions remain recognisable at a glance without reading
   as warning/error banners.
4. Gutter, minimap, and overview-ruler indicators use the same hue family.
5. Inline diagnostics, selection, and bracket-match decorations remain visible
   through diff overlays.
