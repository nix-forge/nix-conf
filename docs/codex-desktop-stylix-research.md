# Codex Desktop and Stylix research

Reviewed: 2026-09-08. Scope: the native Desktop appearance controls, their
configuration schema, generated colors, fonts, and code highlighting. This
updates the earlier inspection of build `26.818.61809`.

## Answer

Use Codex Desktop's native Chrome-theme settings for the Carbon palette and
fonts, and select a bundled code theme separately. The app computes hover,
selection, border, and secondary-text colors from a small set of inputs. It
does not expose VS Code's color-key registry or accept a VS Code theme extension
through its appearance configuration.

The public [OpenAI Settings reference](https://learn.chatgpt.com/docs/reference/settings#appearance)
documents light, dark, and system modes, custom colors and fonts, contrast,
translucency, theme sharing, pointer cursors, and separate UI/code sizes. The
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
still omits the Desktop appearance-file schema. Its `tui.theme` setting controls
terminal UI syntax highlighting, so it cannot configure the Desktop theme.

The recommendations below follow the locally shipped implementation. Treat
these configuration fields as a small compatibility boundary and check them
when updating the application. Do not copy the full VS Code theme into Codex,
modify the application bundle, or maintain a CSS override for every generated
color.

## Sources and version boundary

| Evidence | Version or retrieval | What it establishes |
| --- | --- | --- |
| [OpenAI Settings reference](https://learn.chatgpt.com/docs/reference/settings#appearance) | Retrieved 2026-09-08 | Supported user-facing appearance controls. |
| [OpenAI configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) | Retrieved 2026-09-08 | Public configuration fields and the separate TUI theme setting. |
| [OpenAI changelog](https://learn.chatgpt.com/docs/changelog) | Retrieved 2026-09-08 | Native custom colors, fonts, and sharing were announced with app `26.312`. |
| Installed `openai-codex-electron` package | `26.901.41600`, Linux | Appearance validators, setting storage, theme resolution, syntax presets, and CSS generation inspected in the shipped JavaScript. |
| [Repository package source](../pkgs/pkgs/by-name/op/openai-codex-desktop/source.nix) | `26.901.51231` at review time | Newer first-party package extracted locally; the appearance registry and Chrome validator match the installed version. |
| [Official Linux stable package index](https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages.gz) | Retrieved 2026-09-08 | Latest indexed Linux package is `26.901.51231`. |

The installed implementation evidence comes from the extracted application
resource `webview/assets/app-initial-36a3a1b7313c.js`. Its SHA-256 is
`5e4b002d1b6a5cb2edef63e0e8bde74613d78124f487f054d7047744a501bcdc`.
The resource contains the appearance setting registry, Chrome-theme validator,
code-theme registry, and color generator. The newer package resource is
`webview/assets/app-initial-9e28b0395ba3.js`, with SHA-256
`77a54fd9f0025d2e2a7cafbfe8aec90a52dd667ee36290a57adf9745e9e5c944`.
Its appearance settings and Chrome validator have the same fields, defaults,
and constraints. Terminal rendering in the installed build also uses
`webview/assets/xterm-window-zoom-e315d4d8be01.js`.

These are first-party application resources inspected locally, not a public
source repository or a promised configuration API. Raw extracted resources and
runtime captures stay outside this repository. The fetched public pages did
not publish a complete appearance schema. The schema inventory here comes
from inspection of the two first-party application builds, not those pages.

## Complete reviewed appearance-setting inventory

Both reviewed appearance registries have ten configuration-backed settings. They
are stored under `[desktop]` in the active `$CODEX_HOME/config.toml`.

| Setting | Accepted value | App default | Integration guidance |
| --- | --- | --- | --- |
| `appearanceTheme` | `system`, `light`, `dark` | `system` | Use `dark` for either Carbon variant. |
| `appearanceLightChromeTheme` | Chrome-theme object below | Unset | Keep the app's light defaults unless supplying a separately reviewed light palette. |
| `appearanceDarkChromeTheme` | Chrome-theme object below | Unset | Configure Carbon roles here. |
| `appearanceLightCodeThemeId` | Registered code-theme ID | `codex` | The ID must have a light variant. |
| `appearanceDarkCodeThemeId` | Registered code-theme ID | `codex` | Choose a tested dark preset independently of the UI palette. |
| `appearanceDiffMarkerStyle` | `color`, `symbols` | `color` | Symbols can add a non-color cue to review diffs. |
| `sansFontSize` | Number from 11 through 16 | `14` | Preserve the selected readable UI size. The validator does not require an integer. |
| `codeFontSize` | Number from 8 through 24 | `12` | Applies to code across the app; it is independent of UI size. |
| `useFontSmoothing` | Boolean | `true` | The inspected CSS implementation applies antialiasing only on macOS. |
| `usePointerCursors` | Boolean | `false` | Enabling it adds a pointer cue on interactive controls. |

Two adjacent appearance preferences use global state rather than the
configuration file. `dock-icon-preference` selects the macOS Dock icon and
accepts `app-default` or `codex-system`. Its default is `app-default`; legacy
`codex-light` and `codex-dark` values normalize to `codex-system`.
`reduced-motion-preference` accepts `system`, `on`, or `off`, with `system` as
the default. Do not invent `[desktop]` TOML keys for either. Window zoom also
has separate persisted state and is not a font-size or Chrome-theme field.

### Chrome-theme object

Both the light and dark fields accept the same object. A supplied object needs
all required entries, including its nested required entries. Optional fields
may be omitted. Every color is exactly six hexadecimal digits prefixed by
`#`; alpha channels and CSS color functions are not accepted here.

| Field | Type and requirement | Purpose |
| --- | --- | --- |
| `surface` | Required color | Base application background. |
| `ink` | Required color | Base foreground used in derived text and control colors. |
| `accent` | Required color | Accent source color. |
| `accentSource` | Optional `chatgpt` or `custom` | Whether account accent selection may replace the configured accent. |
| `contrast` | Required integer from 0 through 100 | Input to the app's color interpolation; not a measured contrast ratio. |
| `opaqueWindows` | Required boolean | Native window opacity preference. |
| `fonts` | Required object | Font-family choices and optional face metadata. |
| `fonts.ui` | Required string or null | UI font family; null uses the app fallback. |
| `fonts.code` | Required string or null | Code font family; null uses the app fallback. |
| `fonts.content` | Optional string or null | Separate content font; omission follows the UI fallback. |
| `fonts.uiFace` | Optional font-face object | Specific UI face selected through the font picker. |
| `fonts.codeFace` | Optional font-face object | Specific code face selected through the font picker. |
| `fonts.contentFace` | Optional font-face object | Specific content face selected through the font picker. |
| `semanticColors` | Required object | Diff and skill colors, separate from language syntax rules. |
| `semanticColors.diffAdded` | Required color | Added-line decorations and derived added-line backgrounds. |
| `semanticColors.diffRemoved` | Required color | Removed-line decorations and derived removed-line backgrounds. |
| `semanticColors.skill` | Required color | Skill accent. |

Each optional font-face object has three required string fields, `family`,
`fullName`, and `postscriptName`. Leave these objects out for a portable
family-based configuration. When changing a font family, clear stale face
metadata for that family. The native settings UI follows that same rule.

`accentSource = "custom"` makes the palette's ownership explicit. With
`"chatgpt"`, the runtime may substitute the account accent even when `accent`
is also present. Older custom blocks without `accentSource` generally retain
their color, but relying on the app's inference makes future changes harder to
reason about.

The optional content font and pointer-cursor setting were absent from the
older inventory. They are genuine current controls. Their absence from a
configuration is not automatically a bug because the app supplies defaults.

## Code themes and syntax highlighting

The installed schema accepts these 28 preset IDs. The registry associates each
with bundled TextMate/Shiki theme data. Some support only one appearance mode.

| ID | Dark preset | Light preset |
| --- | --- | --- |
| `absolutely` | Absolutely Dark | Absolutely Light |
| `ayu` | ayu-dark | None |
| `catppuccin` | catppuccin-mocha | catppuccin-latte |
| `codex` | Codex Dark | Codex Light |
| `dracula` | dracula | None |
| `everforest` | everforest-dark | everforest-light |
| `github` | github-dark-default | github-light-default |
| `gruvbox` | gruvbox-dark-medium | gruvbox-light-medium |
| `linear` | Linear Dark | Linear Light |
| `lobster` | Lobster Dark | None |
| `material` | material-theme-darker | None |
| `matrix` | Matrix Dark | None |
| `monokai` | monokai | None |
| `night-owl` | night-owl | None |
| `nord` | nord | None |
| `notion` | Notion Dark | Notion Light |
| `oscurange` | Oscurange | None |
| `one` | one-dark-pro | one-light |
| `proof` | None | Proof Light |
| `raycast` | Raycast Dark | Raycast Light |
| `rose-pine` | rose-pine-moon | rose-pine-dawn |
| `sentry` | Sentry Dark | None |
| `solarized` | solarized-dark | solarized-light |
| `temple` | Temple Dark | None |
| `tokyo-night` | tokyo-night | None |
| `vercel` | Vercel Dark | Vercel Light |
| `vscode-plus` | dark-plus | light-plus |
| `xcode` | Xcode Dark | Xcode Light |

A registered ID that lacks the requested variant falls back to Codex in the
inspected resolver. Test the effective result as well as schema acceptance.
There is no appearance field for a custom theme path, TextMate rule array, or
VS Code semantic-token customization. The import function checks both the
appearance variant and an existing preset ID. Theme sharing therefore does
not provide an arbitrary syntax-theme loader. The shipped share format has a
`codex-theme-v1:` prefix followed by JSON containing `codeThemeId`, `theme`, and
`variant`. Use the native copy/import controls to exchange it; it is separate
from a VS Code theme JSON file.

Choosing a preset in the native theme picker also loads its Chrome-theme seed.
That operation can replace background, foreground, accent, and semantic
colors. A declarative integration should write the code-theme ID and its own
Chrome object separately so a syntax choice does not silently replace Carbon.
The same distinction matters when manually adjusting the theme later.

Test representative source text with the shipped grammars and renderer.
Include comments, strings, functions, properties, types, punctuation,
Markdown emphasis, and diff backgrounds. A valid color setting cannot repair
a missing grammar or reproduce VS Code's language-server semantic tokens.
The Desktop `semanticColors` object only covers the three UI roles listed
above.

Rich Markdown editing also has a separate CodeMirror highlight style. In
`file-editor-theme-7743818d368d.js`, links use the app information color, quotes
use secondary text, syntax markers use tertiary text, and emphasis uses
italic, semibold, or strikethrough. Inline code uses the code font and dedicated
inline-code colors. Source-file editing reads the configured code-theme IDs.
Checking one renderer does not establish that the other follows the same
syntax rules.

## Derived colors and review priorities

The installed Chrome generator produces 67 CSS variables from the compact
Chrome object. Its calculations cover buttons in normal/hover/active states,
focus borders, menus, elevated backgrounds, primary/secondary/tertiary text,
icons, selections, and diff decorations. These variables are implementation
outputs, not 67 additional supported configuration keys.

The `contrast` control changes interpolation weights and alpha values. A value
of 60 is the app's dark default; it does not promise a particular text contrast
ratio. Increasing it can improve secondary text and control feedback, but
foreground/background pairs must be checked after alpha compositing on the
actual background. The review should include elevated menus and code/diff
backgrounds as well as the main window.

Use readable text, visible keyboard focus, and distinguishable hover states as
acceptance criteria. Pointer cursors provide an extra signal but do not repair
an invisible highlight. For diffs, a symbol marker is useful when color alone
is ambiguous. Preserve the selected font sizes and test wrapping and glyph
rendering rather than shrinking text to fit a preview.

The integrated terminal reads foreground, background, cursor, selection, and
16 ANSI colors from the app's computed terminal CSS variables. The inspected
appearance schema exposes no independent ANSI palette or terminal minimum
contrast setting. Do not assume the VS Code terminal configuration or its
contrast correction applies here. Text emitted by terminal applications needs
its own checks.

## Implication for this repository

The existing integration lives in
[Codex theme target](../modules/shared/stylix/targets/codex-desktop/home.nix) and its
[appearance updater](../modules/shared/stylix/targets/codex-desktop/configure-codex-desktop-appearance.sh.in).
The package selection belongs to
[`codex-app.nix`](../modules/home/dev/agentic-gui/codex-app.nix).

Keep the palette mapping small and consistent with the shared appearance
roles: `surface`, `text`, `accent`, `diffAdded`, `diffRemoved`, and `special`.
Use the configured sans-serif and monospace families. Explicit dark mode is
appropriate for Carbon and OLED; an unconfigured light block can safely keep
the app's defaults. A dark palette should not be copied into the light block
merely to fill every field.

The updater must preserve other settings in the active config, including
unknown future fields and unrelated Desktop preferences. TOML permits quoted
keys, comments after table headers, and multiline strings, so a line-oriented
search-and-replace is not a complete TOML merge. Validate an updated document
before replacing the original, retain permissions, and make the update
idempotent. When a font family changes, avoid retaining contradictory native
font-face metadata.

## Validation and limits

This research inspected the installed Linux `26.901.41600` validators,
appearance registry, preset registry, normalizer, color generator, native font
handling, and terminal theme conversion. Public documentation was rechecked
on 2026-09-08. The newer `26.901.51231` registry and Chrome validator were
compared directly with the installed build and had the same configuration
fields, defaults, and constraints. The preset mapping and renderer details
above were inspected in `26.901.41600`.

The research alone does not prove every control renders correctly, every
language is highlighted, or a newer package behaves identically. It does not
establish native macOS or Windows rendering, and font smoothing was traced in
source rather than tested on macOS. The runtime checks and implementation results below provide separate evidence.

### Implemented changes

The integration now sets `accentSource = "custom"` so an account accent cannot
replace Carbon's accent. Contrast is 85 for both Carbon variants. The prior
value of 60 made enabled menu labels and project-picker text too dim. The
standard Carbon elevated background also needed more contrast than OLED.
`appearanceDiffMarkerStyle = "symbols"` adds plus/minus markers alongside diff
colors. The selected code preset remains `codex`; both font sizes remain 16.
No additional content-font override is needed because its default follows the
UI family. The light Chrome theme remains app-owned.

The updater now uses TOMLKit to merge the managed fields and the standard
library's TOML parser to check serialization. The old line-based updater
produced duplicate `[desktop]` tables when a valid table header had a trailing
comment. The replacement handles quoted headers, dotted keys, inline tables,
and table-shaped text inside multiline strings. It preserves unrelated values
and ordinary comments. Inline or fragmented dotted tables being changed are
normalized to ordinary tables, so their internal formatting can change.

Updates retain permissions and writable symlinks, skip an unchanged file, and
replace changed files atomically. A check immediately before replacement
rejects detected concurrent edits; it is not a shared lock with the application.
Malformed input remains untouched. Managed UI/code font-face metadata is
cleared so it cannot contradict the selected families; user-owned content
font settings remain intact.

### Runtime verification

The [derived color inventory](assets/codex-theme-audit.json) records all 67
native outputs for the final OLED configuration. The two reviewed app builds
returned identical values. Their own validators accepted all nine supplied
appearance settings, including the complete dark Chrome object. The tenth
setting, the light Chrome object, is deliberately omitted. Three invalid
Chrome objects exercised out-of-range contrast, a short hex color, and an
unknown accent source; all were rejected.

| Check | Result |
| --- | --- |
| Built configuration updater | Eight standard-library regression tests passed, including valid TOML variants, unrelated-state preservation, permissions, idempotence, invalid input and symlinks. |
| Installed app, Carbon and OLED | Five enabled control labels and an elevated-description color pair passed the 4.5:1 text target. Native menu-button CSS changed its fill for hover and keyboard-focus states. |
| Latest app, Carbon and OLED | Native validators, generated colors, elevated-description contrast, rich Markdown styles and syntax-worker checks passed. Its isolated profile stayed at sign-in, so full menu/control rendering was not tested there. |
| Syntax worker | Each build highlighted 136 nonempty spans across 12 language fixtures. All measured spans exceeded 4.5:1 on the code theme's background; the lowest ratio was 5.80:1. |
| Rich Markdown styles | The app's CodeMirror extension rendered semibold strong text, italic emphasis, underlined links and strikethrough using its actual generated classes. |

For OLED, enabled menu-label contrast improved from 4.00:1 to 6.14:1, and the
project-picker label from 4.04:1 to 6.05:1. Elevated description text reaches
4.86:1 on OLED and 4.52:1 on standard Carbon. These are targeted measurements,
not an accessibility certification. Hover/focus testing forces CSS states on
the actual menu button to avoid compositor focus interference; it verifies
style rules, not physical pointer-event delivery or native popup menus.

The syntax fixtures cover TypeScript, JavaScript, Python, Nix, JSON, YAML,
HTML, CSS, C++, Java, shell and Markdown. They run the app's shipped Shiki
worker with its bundled grammars and Codex Dark preset, then measure its
rendered spans. This is lexical highlighting; Desktop does not acquire the
VS Code language-server setup through the shared palette. Markdown source
uses a distinct color for bold markup and italic typography for emphasis.
The separate rich Markdown editor uses weight 600 for strong text. The
CodeMirror check supplies semantic tags directly and does not test its entire
editing/parser workflow.

The reusable checks are
[configuration regression tests](../tests/codex/test_appearance_config.py) and
[native runtime checks](../tests/codex/check_theme_runtime.mjs). Build the
appearance wrapper referenced by the home profile's activation entry for the
native test. The configuration tests run the updater with independent settings
fixtures through pytest. The runtime test needs a private extraction of the selected app's `webview/assets`, the generated appearance
JSON referenced by the wrapper, and an isolated app debugging endpoint.

```sh
workstation-task nix develop .#tests --command \
  python3 -m pytest tests/codex/test_appearance_config.py
CODEX_HOME="$private_directory/config" \
  CODEX_ELECTRON_USER_DATA_PATH="$private_directory/profile" \
  "$codex_app" --user-data-dir="$private_directory/profile" \
  --remote-debugging-port=9345
node tests/codex/check_theme_runtime.mjs \
  http://127.0.0.1:9345 "$extracted_assets" "$appearance_json"
```

Run the runtime command in a second shell after the isolated window loads.
For a profile at sign-in, `CODEX_THEME_COLORS_ONLY=1` explicitly skips the
unavailable workbench controls while retaining the other checks. The test
imports native validators and applies native theme functions inside that
disposable window. It does not patch the installed application. Its adapter
inspects bundled module exports and must be reviewed if an app update changes
the internal module layout. Do not aim it at an active work session.

Native macOS/Windows menus, actual terminal program output, every review state,
and every language remain outside these checks. After applying appearance
configuration, reopen Codex Desktop to ensure all existing windows load it.
The latest package was built for inspection without replacing the running app.
