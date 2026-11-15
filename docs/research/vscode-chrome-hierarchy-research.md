# VS Code Chrome Hierarchy Research

## Scope

This note evaluates the Carbon Neon VS Code workbench chrome shown in the
screenshots: the visually dominant cyan `Quota reached` item in the status bar
and the lack of separation between the title bar, top activity bar, tab strip,
and editor.

## Findings

### The cyan status item is the wrong role for an informational state

The current Carbon Neon theme maps `statusBarItem.prominentBackground` to the
bright cyan accent. The screenshot's `Quota reached` item is using that
prominent-item role, so it receives a cyan fill and nearly-black text. It is
not inheriting the normal status-bar background.

VS Code describes `statusBarItem.prominentBackground` as the color for a
status-bar item that should stand out to indicate importance. Its extension UX
guidance is stricter: status-bar items should not add custom colors, and a
warning or error background is only appropriate as a last resort because it is
so prominent. A quota state that is visible but not immediately actionable
should therefore use the normal bar surface, with a neutral or modestly tinted
foreground, rather than a full accent fill.

Sources: [Theme color reference: status-bar colors](https://code.visualstudio.com/api/references/theme-color#status-bar-colors), [VS Code Status Bar UX Guidelines](https://code.visualstudio.com/api/ux-guidelines/status-bar).

### Normal status-bar chrome should be quieter than code

The status bar is a secondary, contextual surface. VS Code's own modern dark
theme makes it a dark surface and sets its foreground to `#CCCCCC`, below the
active-tab white and with a low-contrast hover overlay. Catppuccin also uses a
subdued status foreground and gives its prominent status item a neutral surface
instead of its accent fill. This is a useful pattern for Carbon: keep readable
text, but use the muted neutral (`base04`) for the normal status foreground;
reserve brighter neutral text for hover and keyboard focus.

Sources: [VS Code Dark Modern theme](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/dark_modern.json), [Catppuccin VS Code theme source](https://github.com/catppuccin/vscode).

### A compact elevation ladder gives the top chrome structure

The current Carbon theme gives the title bar, top activity bar, tab container,
and editor the same `#0A0A0A` background. It is cohesive but removes useful
spatial cues. VS Code exposes distinct tokens for each of these surfaces. Its
Dark Modern theme uses a small separation: title bar and tab container at
`#181818`, editor and active tab at `#1F1F1F`, and a quiet `#2B2B2B` border.
Its source also uses a translucent inactive-tab foreground and exposes separate
top-activity-bar tokens when the activity bar is placed at the top.

For Carbon, preserve the OLED-black editor as the visual anchor and add only
one very small step of elevation around it:

| Surface | Recommended role |
| --- | --- |
| Title bar | base black (`base00`), with a very subtle divider |
| Top activity bar and tab container | one quiet raised neutral (`base01`) |
| Inactive tab | same quiet neutral, muted text |
| Active tab and editor | base black, bright-neutral title, thin teal top border |
| Status bar | base black or `base01`, muted neutral text, subtle border |

This creates grouping without competing with the editor. Accent color remains
appropriate for a two-pixel active-tab/focus indicator, progress, or an actual
warning/error state, not a persistent full-width or full-item background.

Sources: [Theme-color tokens for the activity bar](https://code.visualstudio.com/api/references/theme-color#activity-bar), [editor groups and tabs](https://code.visualstudio.com/api/references/theme-color#editor-groups--tabs), [VS Code color-token source](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/common/theme.ts#L2024-L2185), [Dark Modern theme](https://github.com/microsoft/vscode/blob/main/extensions/theme-defaults/themes/dark_modern.json).

### Do not solve hierarchy by weakening focus feedback

Lower contrast for passive chrome is desirable here, but keyboard focus and
diagnostic states must remain unambiguous. VS Code provides specific
`focusBorder`, `statusBarItem.focusBorder`, warning, and error tokens for this
purpose. Its accessibility guidance recommends high-contrast themes and
WCAG-aware color choices. The right separation is therefore: quiet passive
labels, strong focus outline, and semantic warning/error colors only when the
state justifies them.

Sources: [Contrast color reference](https://code.visualstudio.com/api/references/theme-color#contrast-colors), [VS Code accessibility guidance](https://code.visualstudio.com/docs/configure/accessibility/accessibility#_high-contrast-theme).

## Recommended Carbon Neon token changes

1. Change the normal status bar foreground from bright neutral (`base05`) to
   muted neutral (`base04`); retain bright neutral only for hover and focused
   items.
2. Set `statusBarItem.prominentBackground` to transparent or the normal
   status-bar surface, and use the muted neutral foreground. This removes the
   cyan `Quota reached` block without hiding the information.
3. Keep teal for `statusBarItem.focusBorder`, the active tab's thin top border,
   and explicit progress/actions. Do not use it as the normal persistent fill
   of an extension status item.
4. Set `activityBarTop.background` and
   `editorGroupHeader.tabsBackground` to the first raised neutral, while
   keeping the title bar and active editor/tab at base black. Add quiet
   `titleBar.border` and `editorGroupHeader.tabsBorder` separators.
5. Preserve Carbon's strong code contrast. The requested reduction applies to
   passive workbench chrome only; it should not lower editor syntax or
   diagnostic contrast.
