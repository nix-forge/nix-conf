# VS Code Token Background Research

## Finding

The warning is correct. VS Code marks `background` within a `tokenColors`
rule as deprecated with the message “Token background colors are currently not
supported.” This applies equally to TextMate `tokenColors` and to the object
form of `semanticTokenColors`.

Source: [VS Code color-theme schema](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/themes/common/colorThemeSchema.ts#L136-L162).

The implementation still parses a TextMate rule's `background` into token
metadata, but the standard DOM token renderer emits only a foreground color
and font styles. Its generated token CSS is likewise foreground-only. That
implementation detail does not make per-token backgrounds a supported theme
feature, and the schema deliberately warns against relying on it.

Sources: [token-theme parsing](https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/languages/supports/tokenization.ts#L81-L100), [DOM token presentation](https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/encodedTokenAttributes.ts#L125-L173), and [generated token CSS](https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/languages/supports/tokenization.ts#L413-L421).

Semantic-token rules are not an alternative for token backgrounds: VS Code
documents only a foreground and typography properties for them. Semantic
highlighting should remain enabled in Carbon because it improves token
classification, but it should be used for foreground/style rules only.

Source: [Semantic Highlight Guide — Theming](https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide#theming).

## Carbon impact

The Carbon templates currently set token-rule backgrounds in two places:

1. The unscoped default rule in `carbon-neon-color-theme.json`.
2. The OLED override in `carbon-neon-oled-color-theme.json`.

They are redundant because both templates already set the supported
`editor.background` workbench color. Keeping them provides no supported
rendering benefit and causes the schema diagnostic.

## Recommended change

Remove those `tokenColors[].settings.background` entries. Keep the default
syntax foreground rule in the standard template, and remove the OLED
`tokenColors` block entirely if it has no remaining rules. Use
`colors.editor.background` as the sole editor-surface definition; it remains
derived from the selected Stylix palette, so switching themes continues to
work as intended.

For intentional contextual highlights, use the documented workbench color
tokens instead of trying to attach a background to a lexical or semantic
token:

| Intent | Supported color tokens |
| --- | --- |
| Selection and matching selected text | `editor.selectionBackground`, `editor.selectionHighlightBackground` |
| Symbol read/write references | `editor.wordHighlightBackground`, `editor.wordHighlightStrongBackground` |
| Find results | `editor.findMatchBackground`, `editor.findMatchHighlightBackground` |
| Current line | `editor.lineHighlightBackground` *or* `editor.lineHighlightBorder` |
| Source-control diffs | `diffEditor.insertedTextBackground`, `diffEditor.removedTextBackground`, and their line/gutter/overview companions |

The editor color reference requires transparent overlays for several of these
roles so diagnostics and other decorations stay visible. It also recommends a
current-line background *or* border, not both. For diffs, it similarly
recommends an inserted/removed text background *or* border, not both.

Sources: [editor colors](https://code.visualstudio.com/api/references/theme-color#editor-colors) and [diff editor colors](https://code.visualstudio.com/api/references/theme-color#diff-editor-colors).

## Decision

Do not suppress the warning or substitute semantic-token backgrounds. Remove
the two unsupported declarations and retain Carbon's existing Stylix-derived
editor, selection, and diff workbench colors. This is the most reliable
solution across VS Code renderers and future releases.
