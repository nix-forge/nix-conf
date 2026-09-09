# VS Code theme schema and highlighting

Reviewed: 2026-09-08. Scope: Carbon Neon and Carbon Neon OLED, the installed
VS Code 1.133.0 compatibility target, and current official theme APIs.

## Answer

The audit corrected shared control contrast, selection visibility, and syntax
fallbacks while retaining one shared Carbon theme with a small OLED override.
Validate the generated
JSON against the running editor's registered schemas, and review upstream
additions when updating VS Code. Omitted workbench colors can inherit useful
defaults. Explicitly configure roles where Carbon's near-black backgrounds make
those defaults unreadable or erase interaction feedback.

Syntax needs two matching layers: TextMate rules for immediate highlighting and
semantic rules for the language server's more precise classifications. Their
colors should agree when they describe the same role. A schema check cannot
prove that a language grammar emits a particular scope or that a language server
provides semantic tokens.

These are repository recommendations based on the sources below. They do not
claim that every registered color needs an override or that every language has
been tested visually.

## Findings and sources

### Define what "latest" means

Microsoft's latest stable release at review time is
[1.136.1](https://github.com/microsoft/vscode/releases/tag/1.136.1), released
September 3, 2026. Its source revision is
[`a44adf7f53e00964ab890f9f8758a334f1fc15bc`](https://github.com/microsoft/vscode/commit/a44adf7f53e00964ab890f9f8758a334f1fc15bc).
The [1.136 release notes](https://code.visualstudio.com/updates/v1_136) identify
the initial release as September 2. The development branch resolved to
[`1bea02a98ebdc249e0fcbe76f104f4b7e8c00049`](https://github.com/microsoft/vscode/commit/1bea02a98ebdc249e0fcbe76f104f4b7e8c00049)
on September 8. Main is a separate comparison target, not a stable release.

Use the installed release to judge present behavior and latest stable to judge
forward compatibility. Report development-only additions separately. Updating
the editor package is a separate decision from correcting the theme.

### Review the complete schema structure

The official color-theme schema links three registries rather than enumerating
every permitted color in one static file.

| Part | Review requirements |
| --- | --- |
| `colors` | Registered workbench identifiers and hexadecimal values, or `default`. Check deprecations and required transparency. |
| `tokenColors` | A relative TextMate theme path or an array of rules. Each rule requires `settings`; its optional `scope` accepts a string or array of strings. |
| TextMate `settings` | `foreground`, `fontStyle`, and, in 1.136.1, `fontFamily`, `fontSize`, and `lineHeight`. `background` remains deprecated and unsupported. |
| `semanticHighlighting` | Boolean opt-in to semantic highlighting when the editor setting delegates to the theme. |
| `semanticTokenColors` | Selector-to-style map. Check selector syntax and each style property independently. |

The TextMate scope suggestions are examples, not a closed vocabulary. The root
schema allows additional properties, so passing it does not verify every
metadata field. The newer font metrics need no declaration unless the theme
intentionally changes typography. Keep them unset for Carbon's uniform code
layout and older-editor compatibility. Source:
[1.136.1 theme schema](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/workbench/services/themes/common/colorThemeSchema.ts).

Workbench registrations supply defaults, deprecation messages, and transparency
requirements. Defaults can refer to another color or compute a derived color.
`default` removes a theme override and restores registry resolution. A missing
override therefore needs its resolved result inspected before it is classified
as a defect. This is why copying the entire registry into Carbon would add
maintenance without establishing visual correctness. Source:
[color registry implementation](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/platform/theme/common/colorUtils.ts).

Extensions can contribute colors, semantic types, modifiers, and fallback
scopes. The effective schema depends on the installed contributions; a core-only
identifier list cannot reject every extension-specific key as invalid. Record
which extension owns such a key. Sources:
[color contributions](https://code.visualstudio.com/api/references/contribution-points#contributescolors)
and [semantic contributions](https://code.visualstudio.com/api/references/contribution-points#contributessemantictokentypes).

### Preserve inheritance and remove ineffective rules

The loader reads `include` before the including file. Child workbench colors
override parent values, and child TextMate and semantic rules append after
inherited rules. Carbon OLED should retain this arrangement so syntax repairs
apply to both variants. The loader also constructs the default token colors
from `editor.foreground` and `editor.background`; unscoped theme token rules
do not replace that default.

Semantic resolution scores matching rules per style property. Explicit semantic
properties take precedence over fallback scope styling. Equal-scoring later
rules win. User customization layers can change the effective result, so inspect
the resolved theme as well as its source. Source:
[theme loader and style resolution](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/workbench/services/themes/common/colorThemeData.ts).

### Make lexical and semantic colors agree

TextMate tokenization supplies immediate syntax classification. Semantic tokens
arrive from language providers and refine it, sometimes after a delay. The
official scope inspector identifies both token classifications and the rules
that colored them. Use `Developer: Inspect Editor Tokens and Scopes` on actual
language examples rather than inferring behavior from selector names. Source:
[syntax highlighting guide](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide).

Keep `semanticHighlighting: true`; Microsoft encourages theme authors to opt
in. A semantic selector has the form
`(*|tokenType)(.tokenModifier)*(:tokenLanguage)?`. If no explicit style matches,
VS Code can map semantic classifications to TextMate scopes. Custom token
subtypes inherit semantic styling from their parent type, but their fallback
scope maps require their own contributions. Semantic foreground transparency is
unsupported. Source:
[semantic highlighting guide](https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide).

Use foreground colors for roles and individual boolean properties for additive
styles. For example, `"*.deprecated": { "strikethrough": true }` preserves
the role's color and other typography. `fontStyle` resets all styles it does not
name and overrides the boolean fields. The registry also retains a deprecated
`member` type; use `method`. Its fallback mappings show which lexical scopes
need coverage for types, functions, parameters, properties, and constants.
Source:
[semantic classification registry](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/platform/theme/common/tokenClassificationRegistry.ts).

The pre-audit Carbon rules exposed these concrete review targets:

| Role | Mismatch or gap to address |
| --- | --- |
| Operators | Generic lexical `keyword` gave purple while semantic `operator` gave the accent. |
| Regular expressions | Generic lexical `string` gave green while semantic `regexp` used the regex color. |
| Properties | Generic lexical `variable` gave normal text while semantic `property` used the accent. |
| Decorators | Function-like fallback could use the function color while semantic `decorator` used the warning palette color. |
| Classes and namespaces | Some common grammar scopes had no matching type rule. |
| Markup | Bold, italic, links, and changed/inserted/deleted text lacked explicit treatment. |

These are observations of the repository's pre-audit templates, not claims
that every grammar emits those classifications. Compare the resulting rules in
the [shared theme](../modules/shared/stylix/targets/vscode/carbon-neon/themes/carbon-neon-color-theme.nix).
The official [Dark+ theme](https://github.com/microsoft/vscode/blob/1.136.1/extensions/theme-defaults/themes/dark_plus.json)
provides useful examples of established class, namespace, escape, constant,
regex, and language-specific scopes. Adapt only the relevant selectors. Avoid
a universal semantic foreground or broad `meta.*` color that masks more useful
classifications.

### Check states on their actual backgrounds

Menus, lists, quick picks, and suggestions share some fallback colors, but
components choose their own roles. A valid selection color can still be
identical to a popup background. Test menu hover, submenu hover, keyboard focus,
active selection, inactive selection, and drag feedback separately. Sources:
[component style mapping](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/platform/theme/browser/defaultStyles.ts),
[list colors](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/platform/theme/common/colors/listColors.ts),
[menu colors](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/platform/theme/common/colors/menuColors.ts),
and [quick-pick colors](https://github.com/microsoft/vscode/blob/1.136.1/src/vs/platform/theme/common/colors/quickpickColors.ts).

The official color reference distinguishes foregrounds, backgrounds, borders,
and overlays. Several editor highlights require transparency so decorations
remain visible. Contrast borders are mainly intended for high-contrast themes;
Carbon's `vs-dark` registration does not make it a high-contrast accessibility
theme. Source:
[theme color reference](https://code.visualstudio.com/api/references/theme-color).

Use WCAG's 4.5:1 normal-text ratio as a design target for code and enabled UI
labels, measured against the rendered background after compositing alpha.
Disabled controls have an exception. This numerical check supports the design;
it does not certify the whole editor's accessibility. Source:
[WCAG text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).

Use a 3:1 target against adjacent colors for essential component boundaries
and state indicators. Do not misapply it as a mandatory 3:1 difference between
every hovered and unhovered fill: the requirement concerns information needed
to identify the component or state. Clear focus outlines can provide that
information while preserving subtle fills. Source:
[WCAG non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).

## Validation and limits

### Complete runtime color inventory

An isolated Linux audit loaded the generated Carbon theme in official
VS Code 1.133.0 and 1.136.1, including their bundled extensions. It read the
registered schemas through `vscode.workspace.fs.readFile` and captured resolved
workbench CSS colors. The schemas contained 948 and 978 workbench identifiers,
respectively. The [complete identifier inventory](assets/vscode-theme-schema-audit.json)
records each latest color, its resolved value after the fixes, its configured,
inherited or unset status, and its transparency and deprecation flags.
Latest stable added 30 identifiers and removed none. These counts
describe the captured installations, not every possible third-party extension.

Every latest identifier was assigned to one of the following groups and its
description and resolved value reviewed. The table records pre-fix findings.
It is a color inventory review, not a claim that every component was opened.

| Group | Colors | Assessment and resulting priority |
| --- | ---: | --- |
| Shared controls, typography, charts, and foundations | 100 | Shared control defaults generally preserve contrast. Raise muted input text where its background reduces contrast below the chosen text target. Chart series retain distinct upstream colors. |
| Chrome, navigation, and interaction | 219 | Corrected menu and picker roles resolve to distinct fills. Modern tab and activity-bar defaults already inherit those colors. Legacy tab hover needs a separate behavior check. |
| Editor, minimap, and symbol icons | 258 | Fix near-black comment indicators and an invisible pending-edit minimap overlay. Keep diagnostic, cursor, symbol-icon, and selection roles distinct. |
| Diffs, merge conflicts, and source control | 65 | Preserve translucent diff layers and conflict distinctions. Fix the source-control history hover badge's foreground/background pair. |
| Terminal | 61 | Fix the near-black command guide and give find matches a transparent overlay. ANSI colors and terminal selections already use Carbon's palette. |
| Debugging | 36 | Upstream execution, breakpoint, and exception colors remain distinguishable. Matching debug-value syntax colors to Carbon is optional consistency work. |
| Notebooks and interactive editors | 26 | Focus inherits the accent; inactive selection uses a subtle fill. Verify inactive cell selection visually before strengthening it. |
| Chat, inline edits, and agent sessions | 89 | Shared inputs and inline diff roles inherit Carbon. Preserve specialized voice, progress, and request states pending component tests. |
| Notifications | 14 | Backgrounds, labels, links, and severity icons inherit the intended palette. |
| Testing and problems | 37 | Severity colors and coverage overlays are present. Retired-test fading is an intentional state, not a missing color. |
| Settings, extensions, profiles, and onboarding | 47 | Settings focus/hover and extension buttons derive visible shared states. Keep upstream profile and onboarding defaults. |
| Search, peek, output, ports, browser, and comments | 26 | Fix the running-process port indicator. Peek's blue editor background is an optional palette-consistency change, not an invisible state. |
| Total | 978 | All registered identifiers in the captured latest installation. |

The most useful measurements from the black-editor capture were:

| Role | Resolved colors before fixes | Finding |
| --- | --- | --- |
| `scmGraph.historyItemHoverDefaultLabelForeground` and its background | `#D9D9D9` on `#80CBC4` | 1.32:1 text contrast. Use the dark badge foreground. |
| Running-port icon, terminal command guide, comment range and overview indicators | `#101213` on `#000000` | 1.12:1 contrast. These inherited fills are too weak for foreground indicators. |
| `minimap.chatEditHighlight` | Black at 60% alpha over black | No visible color change. Use a translucent visible color. |
| Input placeholder | `#7A7A80` on `#161718` | 4.21:1, below the selected 4.5:1 text target. |
| Modern tab/activity item hover | `#FFFFFF` on `#383838` | Shared hover inheritance works; no new override is needed. |

The indicator row covers `ports.iconRunningProcessForeground`,
`terminalCommandGuide.foreground`, `editorGutter.commentRangeForeground`, and
the three `editorOverviewRuler.comment*Foreground` roles. The measurements
identify color-pair defects; component rendering still determines the final
visible area and background.

### New identifiers, deprecations, and transparency

The 30 additions comprise 25 modern activity-bar/tab identifiers, `editor.border`,
two agent-window borders, and two chat search-match backgrounds. Four of the
new `modernActivityBar` active/hover identifiers are already deprecated aliases
for `modernActivityBarItem` properties. Their absent CSS values do not establish
an invisible state: the replacement properties resolve to visible values.

Dereferencing the complete schema found eight deprecated identifiers. Besides
those four modern aliases, they are `quickInput.list.focusBackground`,
`editorIndentGuide.background`, `editorIndentGuide.activeBackground`, and
`editorActiveLineNumber.foreground`. None should be added to Carbon. Check
deprecations inside schema references, not only on the outer property objects.

The capture also contained 59 properties carrying a transparency constraint.
Eight resolved upstream defaults were nevertheless opaque: the terminal's
current find-match background and seven chat foreground, shimmer, or animated
border/glow roles. This is a distinction between validation of explicit theme
values and upstream default resolution. Do not change chat text opacity merely
to make inherited defaults match the schema metadata. For editor and terminal
highlight overlays, preserve content through a transparent fill and verify the
rendered result.

The pinned main source adds six literal color registrations beyond 1.136.1:
`statusBar.inactiveBackground`, `modernPanel.border`,
`modernSash.gripForeground`, `modernUI.shellBackground`,
`modernUI.inactiveShellBackground`, and `chat.statusBackground`. It also raises
the shared surface-border default's foreground contribution from 10% to 15%.
These are development-source observations, not colors missing from the latest
stable schema. Keep their upstream fallbacks until a released editor provides
a reason to override them. Sources:
[pinned main workbench colors](https://github.com/microsoft/vscode/blob/1bea02a98ebdc249e0fcbe76f104f4b7e8c00049/src/vs/workbench/common/theme.ts)
and [pinned main chat colors](https://github.com/microsoft/vscode/blob/1bea02a98ebdc249e0fcbe76f104f4b7e8c00049/src/vs/workbench/contrib/chat/common/widget/chatColors.ts).

Main already removes the transparency requirement from `chat.thinkingShimmer`
and `chat.inputWorkingBorderColor1`, `2`, and `3`. It deprecates the latter two
unused border colors in favor of `chat.inputWorkingBorderColor1`. This supports
leaving those upstream defaults intact. The theme schema, semantic
classification registry, and color-registry schema implementation are unchanged
between the pinned stable and main sources. Source:
[stable-to-main comparison](https://github.com/microsoft/vscode/compare/a44adf7f53e00964ab890f9f8758a334f1fc15bc...1bea02a98ebdc249e0fcbe76f104f4b7e8c00049).

An unset border can mean that no border is needed, or that the component chooses
another indicator. Likewise, `minimap.foregroundOpacity` uses its alpha channel;
its black RGB channels do not make minimap text black. Transparent unused
bracket-color slots and default inactive states need their component semantics
checked before being classified as failures.

### Implemented changes and verification

The shared theme now supplies readable source-control hover labels, port and
comment indicators, terminal command guides, popup descriptions, and input
placeholders. Inactive Explorer selections use a visible dark fill, and focused
selections retain an accent outline. Editor and terminal find highlights use
transparent fills; the pending-edit minimap overlay uses a visible accent.
Existing modern tab/activity defaults remain inherited.

TextMate rules now cover property and attribute names, operators, regex,
decorators, class/namespace scopes, Markdown emphasis and links, and raw diff
roles. The unscoped token rule was removed. Semantic highlighting delegates to
the selected theme through `configuredByTheme`; Carbon continues to opt in.
The deprecated modifier adds strikethrough without replacing a token's color.
The shared palette and the two themes' editor backgrounds are preserved.

Validation ran on Linux using Nix-built theme packages:

| Check | Result |
| --- | --- |
| Workbench, TextMate and semantic schemas, plus theme contribution metadata | Both generated theme files and their contribution entries passed the JSON language servers shipped in 1.133.0 and 1.136.1. Four invalid canaries were rejected in each run. |
| Rendered control colors and interaction states | Both theme variants passed ten contrast-pair checks and six row-state checks on both editor versions. |
| Lexical highlighting | Forty probes passed across twelve language grammars with both editors' bundled TextMate/Oniguruma engines and the configured external grammars. |
| Live scope inspector | Nine probes confirmed TypeScript semantic interface, property, method and parameter colors, plus regex, operator, Python decorator and Markdown bold/italic rendering in 1.136.1. |

The lexical fixtures cover TypeScript, Python, Nix, Markdown, HTML, CSS, JSON,
C++, Java, shell, YAML and diff files. Thirteen probes in the initial seven-language
suite failed before the syntax changes. All ten control contrast pairs failed
before the contrast fixes. For OLED, the SCM hover label improved from 1.32:1 to
11.26:1; placeholder text improved from 4.21:1 to 6.76:1. Description text on a
selected row now reaches 4.97:1. These are observed color-pair measurements,
not a claim that every workbench component meets WCAG.

The schema's semantic style object accepts unknown property names. The test
therefore also rejects fields absent from its declared style properties; a typo
must not silently become an ignored setting. Its invalid canaries exercise an
unknown workbench color, an unsupported token background, an opaque highlight
that requires transparency, and an invalid semantic font style.

The reusable checks are
[interaction and contrast checks](../tests/vscode/check_interaction_colors.mjs),
[schema validation](../tests/vscode/check_theme_schema.mjs), and
[grammar-based syntax checks](../tests/vscode/check_syntax_colors.mjs).
Set the variables below to a built extension directory, the selected editor's
`resources/app` directory, a private schema-output directory, and an extension
directory containing the configured Nix and YAML grammars. `VSCODE_BINARY` can
select an isolated editor version; the default is `code`.

```sh
VSCODE_SCHEMA_OUTPUT="$schema_directory" \
  node tests/vscode/check_interaction_colors.mjs "$theme_extension" 'Carbon Neon OLED'
node tests/vscode/check_theme_schema.mjs \
  "$vscode_app" "$schema_directory" "$theme_extension"
node tests/vscode/check_syntax_colors.mjs \
  "$vscode_app" "$theme_extension/themes/carbon-neon-oled-color-theme.json" \
  "$grammar_extensions"
```

Use schemas exported by the same editor version as the JSON language server.
The exporter saves official runtime schemas in private storage. The schema
check validates the theme contribution part of the extension manifest, not
unrelated extension APIs. It also follows theme includes and rejects cycles or
missing files. The lexical check runs without a graphical session after the
selected editor and grammar packages are available.

### Evidence limits

This research reviewed official documentation, release metadata, source files,
runtime schemas, and resolved colors for the named revisions. Raw source and
runtime captures stay outside the repository. The inventory did not itself
render every workbench view; the targeted runtime and language checks above
provide separate evidence. It establishes schema
coverage and the listed color-pair measurements, not universal visual or
accessibility correctness. Main was compared from official source archives;
it was not built or included in the runtime totals.

On future updates, use generated themes with placeholders resolved and repeat
the representative grammar and runtime checks. Extend fixtures when changing
interpolation, escapes, type classification or language-specific scopes. The official theme workflow
uses an Extension Development Host for live theme testing; this avoids relying
on source-file inspection alone. Source:
[theme development guide](https://code.visualstudio.com/api/extension-guides/color-theme#test-a-new-color-theme).

The actual Python and Nix language servers were not exercised in this audit;
their grammars were. Semantic token availability and classifications still
depend on each language extension. macOS and Windows rendering, native menus,
every notebook/chat/debugger state, and the development branch remain untested.
The existing `terminal.integrated.minimumContrastRatio = 1` deliberately preserves
ANSI palette values. It does not guarantee readable contrast for arbitrary
terminal program output; enabling contrast correction remains a separate
readability-versus-palette choice. Legacy tab hover and inactive notebook-cell
selection also remain candidates for targeted visual review.

## Implication for this repository

Prioritize invisible interaction states, invalid or ineffective declarations,
and syntax mismatches before adding decorative coverage. Keep shared syntax
rules in the base theme, keep OLED changes about backgrounds, and retain
upstream defaults where their resolved colors work. On future VS Code updates,
repeat schema and deprecation checks, then inspect changed default dependencies
and representative rendered states. Preserve measured limitations alongside
passing checks.
