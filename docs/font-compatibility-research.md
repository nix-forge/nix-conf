# Linux browser font compatibility research

Reviewed: 2026-09-17. Scope: general browser font compatibility on Linux/NixOS, with the shared Fontconfig policy, the Firefox-based rendering checks, and the development font checks as the repository context. This note records upstream rules, the resulting policy change, and the deterministic browser test plan.

## Answer

The safe default is conservative: preserve the page's explicit family list and let Fontconfig provide narrow, documented aliases or fallbacks. Test the rendered result in each browser engine, with a fresh profile and an isolated Fontconfig configuration. Do not treat a successful `fc-match` result as proof that CSS loaded, shaped, or measured the same face.

The main failure mode is a rule intended to repair one request changing a wider class of requests. It is especially easy to do with generic-family aliases, strong Fontconfig edits, and private-use characters. CSS defines several cases where the normal installed-font fallback path is constrained or bypassed, including web fonts that shadow installed families and private-use code points that must not use installed fallback.

## Source-backed findings

### Family names and aliases

**Fact.** CSS `font-family` is an ordered list. The user agent moves through the list to find a usable font for a character or cluster. Generic names such as `sans-serif`, `system-ui`, `ui-sans-serif`, `emoji`, `math`, and `fangsong` are CSS keywords, not portable names for a particular installed file. [CSS Fonts Level 4, `font-family`](https://www.w3.org/TR/css-fonts-4/#font-family-prop) and [MDN's generic-family syntax](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/font-family#formal_syntax).

**Fact.** Apple describes San Francisco as its system typeface, but Apple platform names are platform conventions. CSS's portable system generic is `system-ui`; it does not promise an Apple face on Linux. [Apple Typography](https://developer.apple.com/design/human-interface-guidelines/typography) and [CSS Fonts Level 4, system fonts](https://www.w3.org/TR/css-fonts-4/#system-font-def).

**Inference.** The `-apple-system*` and `BlinkMacSystemFont` strings are platform protocol names, not standards-defined generic mappings. Leave them available for later page-owned families on Linux. Do not make a compatibility provider the default for `system-ui`, `sans-serif`, or other generic-only requests without a separate, measured desktop-default decision.

### Style, weight, and variation axes

**Fact.** When a family lacks the requested weight, CSS selects a nearby available weight. User agents can synthesize bold or oblique faces, but the specification calls synthesis an approximation below the quality of a designed face. Variable-font axes are not synthetic faces. [CSS Fonts Level 4, missing weights](https://www.w3.org/TR/css-fonts-4/#missing-weights) and [synthetic-face controls](https://www.w3.org/TR/css-fonts-4/#font-synthesis).

**Fact.** `font-weight`, `font-width`, `font-style`, and `font-optical-sizing` select registered variable-font axes where present. Low-level `font-variation-settings` does not affect fallback selection, ignores unsupported axes, and clamps out-of-range values. [CSS Fonts Level 4, variation resolution](https://www.w3.org/TR/css-fonts-4/#font-variation-settings-prop) and [optical sizing](https://www.w3.org/TR/css-fonts-4/#font-optical-sizing-prop).

**Inference.** A normal-weight sample cannot validate a font family. The regression set needs actual and missing bold, italic, oblique, condensed or expanded, plus at least one variable-font `wght`, `wdth`, `opsz`, and `slnt` or `ital` case when the chosen provider advertises those axes. Test `font-synthesis: none` separately so a synthetic face cannot hide a missing packaged face.

### Installed, local, and web fonts

**Fact.** A web font is scoped to the document that owns its `@font-face` or `FontFaceSet`. A web font with a given CSS family name shadows an installed font with that name in that document. `local()` matches a face's full or PostScript name, not a platform substitution for a family name. [CSS Fonts Level 4, font taxonomy](https://www.w3.org/TR/css-fonts-4/#font-taxonomy), [local font fallback](https://www.w3.org/TR/css-fonts-4/#local-font-fallback), and [MDN `src`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@font-face/src).

**Fact.** Font-display policy can show a fallback before a web font becomes ready, and the exact timing may vary by user agent. [CSS Fonts Level 4, `font-display`](https://www.w3.org/TR/css-fonts-4/#font-display-desc).

**Inference.** Test three distinct paths: an installed family, `@font-face src: local(...)`, and a downloaded WOFF2 that deliberately reuses the installed family name. For the last case, assert the web font wins inside that page and does not leak into another page or profile. Include a delayed response to catch spacing or line-break changes during a `swap` or `fallback` transition.

### Missing glyphs, private use, emoji, and symbols

**Fact.** For a Private-Use Area code point, CSS requires the user agent to consider only non-generic families explicitly named in the CSS list. If none has the glyph, it must show a missing-glyph symbol instead of using installed-font fallback. [CSS Fonts Level 4, character handling](https://www.w3.org/TR/css-fonts-4/#char-handling-issues).

**Fact.** Emoji presentation has semantic inputs beyond the base code point. U+FE0E requests text presentation, U+FE0F requests emoji presentation, and an emoji ZWJ sequence requests a single glyph when one is available. An unsupported ZWJ sequence falls back to separate emoji. [UTS #51, presentation selectors](https://www.unicode.org/reports/tr51/#Emoji_and_Text_Presentation_Selectors) and [ZWJ sequences](https://www.unicode.org/reports/tr51/#Emoji_ZWJ_Sequences).

**Inference.** Do not use a broad PUA-capable symbol font as a generic fallback. PUA assignments are font or protocol specific. The existing [private-use template](../modules/shared/fonts/private-use-fallback.conf.in) uses generated weak rules only after installed named families and excludes generic-only and Apple-platform protocol requests. Keep its provider and visible-glyph tests coupled. Also test the expected missing-glyph result for generic-only PUA CSS, because "repairing" that result would violate the CSS rule.

### Clusters, scripts, direction, and metrics

**Fact.** CSS matches combining marks as clusters so that a base and mark can use the same font when possible. Variation selectors belong with the preceding cluster. Unicode's bidirectional algorithm can reorder a mark and its RTL base during display processing. [CSS Fonts Level 4, cluster matching](https://www.w3.org/TR/css-fonts-4/#cluster-matching) and [UAX #9, nonspacing marks](https://www.unicode.org/reports/tr9/#L3).

**Fact.** A fallback face can change layout even when all glyphs are visible. CSS exposes x-height adjustment and `@font-face` ascent, descent, and line-gap overrides for authors who need to match fallback metrics to a primary web font. User agents may obtain metrics from different font tables. [CSS Fonts Level 4, `font-size-adjust`](https://www.w3.org/TR/css-fonts-4/#font-size-adjust-prop) and [metric overrides](https://www.w3.org/TR/css-fonts-4/#font-metrics-override-desc).

**Inference.** Visual tests should measure more than ink. Capture advance width, line box height, baseline position, wrapping at a fixed width, and monospace cell width. Script coverage needs Japanese, Korean, simplified Chinese, traditional Chinese, Arabic or Hebrew with combining marks, and at least one Indic or Southeast Asian shaping sample. A single CJK glyph does not establish locale-sensitive forms or multi-code-point shaping.

### Fontconfig ordering, bindings, and cache state

**Fact.** A Fontconfig `target="pattern"` rule changes the request before matching. `prepend`, `append`, and bindings affect the family list; aliases express the same kinds of insertion. Fontconfig's documented generic-family constants include the CSS UI and emoji generics. [Fontconfig configuration rules](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#match), [edit operations](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#edit), and [generic-family constants](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#constant).

**Fact.** Fontconfig caches font information under the configured cache directories, normally `$XDG_CACHE_HOME/fontconfig`, and can automatically revalidate configuration files and font directories after the configured rescan interval. [Fontconfig cache directories](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#cachedir) and [rescan](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#rescan).

**Inference.** Treat `fc-match` and `fc-match -s` as diagnostics for the Fontconfig leg only. Tests that compare configuration variants must use an empty cache directory and a newly started browser process. After a deployment, the operational check should record the active configuration with `fc-conflist`, the candidate chain with `fc-match -s`, and the selected file, then restart the browser before judging a rendering change. Do not add routine cache deletion to production policy unless a reproducible stale-cache failure justifies it.

## Existing work, viewed against those rules

These are repository observations, not claims about all Linux browsers.

- [`modules/shared/fonts/default.nix`](../modules/shared/fonts/default.nix) installs the two ordered Linux policy components for NixOS and Home Manager: CSS UI generic role aliases and the generated installed-family PUA fallback. Home Manager gives them priorities 49 and 50; the Darwin branch deliberately installs no generated Fontconfig policy.
- [`modules/shared/fonts/fontconfig.nix`](../modules/shared/fonts/fontconfig.nix) renders the XML templates with the active Stylix role names and the centralized compatibility identifiers using `replaceVarsWith`. The CSS UI rules map `system-ui`, `ui-sans-serif`, and `ui-rounded` to the configured sans role, `ui-serif` to the serif role, and `ui-monospace` to the monospace role. The `system-ui` rule uses Fontconfig's semantic generic value because stock rules prepend platform UI candidates; the UI-specific rules match the first requested family because stock rules can incorrectly classify their names as broad serif/sans/mono generics. Named stacks are not rewritten.
- [`check_font_rendering.py`](../tests/browsers/check_font_rendering.py) uses an isolated Gecko profile. It covers digits and `tabular-nums`, 11 script clusters, four legacy Apple PUA code points from named stacks plus generic-only negative controls, missing-first-family stacks, an Apple-style webfont stack, Apple platform protocol names, and a deterministic loopback local/web/style/variable/emoji matrix. Its separate `webfonts` suite still checks third-party text and icon loading for the uBlock regression.
- [`flake/dev/fonts.nix`](../flake/dev/fonts.nix) sets isolated XDG cache and configuration directories for browser checks, supplies Fontconfig-specific test configurations, and runs the deterministic `compatibility` suite in both the Nix browser check and the interactive font-check app. It also validates Unicode emoji coverage from Unicode's published Emoji 17.0 data. The broader app runs mutant and Apple emoji checks when a browser is supplied.
- The multilingual browser samples now include Japanese, Korean, simplified and traditional Chinese, Arabic, Hebrew, Indic, Southeast Asian, Telugu, Khmer, and Myanmar clusters. They remain fallback/shaping checks rather than a claim of complete locale-specific glyph-form coverage.
- [`modules/shared/stylix/default.nix`](../modules/shared/stylix/default.nix) keeps the extended Fontconfig default lists Linux-only in Home Manager. macOS retains the shared Stylix role values for explicit application targets while native system-font resolution remains Core Text-owned.

## Prioritized test and fix checklist

### P0. Protect selection boundaries

1. Keep the current generic-family non-hijack assertions. Extend them to every generic listed in the policy, including `system-ui`, `ui-serif`, `ui-sans-serif`, `ui-monospace`, `emoji`, `math`, and `fangsong`. Assert selected file as well as family, using `fc-match -s` under the isolated configuration.
2. For each compatibility alias, test the exact requested alias, a named stack ending in a generic, and a generic-only declaration. Test both with and without the rule. The expected difference must be stated before changing the policy.
3. The deterministic `compatibility` suite now covers same-name installed-versus-web shadowing, document isolation, and `local()` full-name or PostScript-name selection using loopback TTF fixtures. The network-backed `webfonts` suite remains opt-in because its purpose is the independent uBlock/filter-list regression.
4. Keep named-stack PUA coverage. Add a generic-only PUA negative control that expects a missing glyph, plus ordinary symbol cases that must use normal fallback rather than the Apple PUA provider.

### P0. Exercise faces and sequences, not just families

1. Render regular, 700 or 800 weight, italic, oblique, and a deliberately unavailable face for every policy provider. Use `font-synthesis: none` for the missing-face case.
2. Add a variable-font fixture with registered axes and assert both computed variation settings and changed canvas metrics or pixels. Cover values at each end of the advertised range and one out-of-range value that must clamp.
3. Test text versus emoji presentation, keycap, regional-indicator flag, skin-tone modifier, and ZWJ sequence. Assert the intended sequence remains one cluster when the provider supports it, while an unsupported sequence has an acceptable decomposed fallback.
4. Add fixed-width tests for ASCII, box drawing, powerline-like symbols, and fallback characters. A font can paint every glyph while breaking terminal or code alignment.

### P1. Make multilingual and layout regressions visible

1. Add Japanese, Korean, simplified Chinese, and traditional Chinese samples with appropriate `lang` tags. Add Arabic or Hebrew mixed with Latin punctuation, and a base-plus-combining-mark sample. Compare canvas pixels and measure the whole cluster, not isolated code points.
2. Add width, line-height, baseline, and fixed-container wrapping assertions for the Apple platform stack, a generic stack, and a web-font transition. Preserve screenshots as diagnostic artifacts only; keep numeric verdicts as the pass condition.
3. Run the same local fixtures in Firefox and a Chromium-family browser. Report engine-specific results separately. Passing Gecko does not establish Blink behavior.

### P1. Make cache behavior reproducible

1. Start each variant with a new Fontconfig cache directory and a new browser profile and process. Record the effective Fontconfig file list and candidate chain in the test output.
2. Add a focused integration check that changes only the isolated configuration between two runs. It should prove that the second fresh browser process sees the new selection. Do not rely on a browser reload.

### P2. Change policy only with a narrow reason

1. Prefer a page-owned web font or a targeted user stylesheet for a known external icon protocol. Add a global Fontconfig fallback only when the provider, mapping, and unwanted-request exclusions are documented and tested.
2. Avoid strong family substitutions except for a clear compatibility alias whose metrics and faces are intentionally equivalent for the requested use. Weak append rules still alter selection, so they need generic, language, and web-font regression tests.
3. Keep cache cleanup and browser-specific settings out of production configuration unless P1 finds a repeatable runtime failure that cannot be handled by normal activation and process restart.

## Validation and limits

This research reviewed the working tree and the linked primary sources on
2026-09-17. The focused Fontconfig selection check passed 13 role/style
selections, 15 CSS UI-generic selections, and four CJK language comparisons;
the emoji coverage check passed all 3,953 Unicode 17 RGI entries. The isolated
Firefox browser check passed 160 digit samples, 11 script clusters, four named
PUA cases plus generic-only negative controls, both Apple alias suites, and the
local compatibility matrix. Native Qt/Pango rendering also passed. The
network-backed third-party web-font suite was not used as the compatibility
gate. Chromium-family behavior, native macOS rendering, and a live
post-activation cache transition remain unverified. CSS Fonts Level 4 is a
Working Draft, so its URL and status should be rechecked when a future change
depends on a draft-only requirement.

## Implication for this repository

The implemented policy direction is conservative: narrow Linux platform
aliases with weak role fallbacks, explicit CSS UI generic role mapping, a
restricted weak PUA compatibility fallback, isolated Fontconfig test inputs,
and browser rendering evidence. The
remaining meaningful coverage gap is a separately provisioned Chromium-family
run; it should reuse the loopback matrix rather than introduce another global
font rule.
