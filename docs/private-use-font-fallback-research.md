# Private-use font fallback research

Reviewed: 2026-09-16. Scope: the Linux Fontconfig rule used to display legacy Apple private-use glyphs in browser title text, including the reported U+F8FF Apple-logo code point.

## Answer

Do not use an unqualified global append. The renderer now scans the font
packages selected for the current Linux profile at build time and emits weak,
exact-first-family rules only for installed named families. An unavailable
first family therefore does not trigger the compatibility provider, so a stack
such as `YouTube Noto, Roboto, Arial, sans-serif` can continue to Roboto. The
original broad rule was not safe: an exact App Store reproduction showed it
prevented Apple's SF Pro webfont from being requested and made Lucida Grande win
ordinary text selection.

It is not a general cure for PUA text. PUA values have no interoperable glyph meaning. CSS requires browsers to consider only non-generic families named in `font-family` for a PUA character, and to show a missing glyph when none covers it. A page that supplies only `sans-serif`, `system-ui`, or another generic can therefore remain broken even when the provider is installed. The implementation now states that boundary in the Fontconfig rule and tests several visible legacy Apple assignments rather than encoding only the reported icon.

## Source claims

CSS Fonts Level 4 says that a PUA character may match only non-generic families in the CSS family list. If none has the glyph, the browser must use a missing-glyph symbol instead of installed-font fallback. The same section describes installed fonts named directly by family as covering the Unicode space for matching purposes. This rule is why the distinction between a named stack and a generic-only declaration matters. [CSS Fonts Level 4, character handling](https://drafts.csswg.org/css-fonts/#char-handling-issues) and [first available font](https://drafts.csswg.org/css-fonts/#first-available-font).

Gecko implements the same policy. Its text-run code does not search preference fonts or system fonts for PUA or unassigned characters, because they have no standard meaning. It retains the candidate from the explicit font group. This means Firefox font preferences are not a reliable way to repair an arbitrary PUA glyph. [Gecko `gfxTextRun.cpp`](https://searchfox.org/mozilla-central/source/gfx/thebes/gfxTextRun.cpp).

The cross-browser Web Platform Test maintained through Chromium's mirror tests this CSS rule with generic families followed by one non-generic font. Its revision `be3b3a04c6a33b3bb31d2b257d6179f83045387f`, dated 2025-12-17, quotes the requirement and explains why the test needs a real PUA-capable named face. That is useful evidence for Blink-family conformance, but it does not establish the behavior of every Chromium build or platform integration. [WPT change](https://chromium.googlesource.com/external/w3c/web-platform-tests/+/be3b3a04c6a33b3bb31d2b257d6179f83045387f).

Fontconfig edits request patterns in configuration order. A `target="pattern"` edit changes the request before selection; `append` adds the family at the end, and `binding="weak"` records the added family as weak. Weak family values rank below language matching, unlike strong ones. These semantics support a compatibility fallback without substituting the first requested family. [Fontconfig matching and bindings](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#fontmatching) and [configuration-edit reference](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#edit).

An explicit provider is the other sound pattern. Chromium's Secure Shell bundles Powerline PUA glyphs as separate web fonts, gives each one a matching metric design, constrains it with `unicode-range`, and names it after the normal monospaced family in CSS. That project chooses a document-owned provider because its PUA assignment is its own icon protocol. [Chromium Secure Shell font design](https://chromium.googlesource.com/apps/libapps/+/HEAD/nassh/docs/fonts.md).

## Approaches compared

| Approach | What it fixes | Limits and judgment |
| --- | --- | --- |
| Browser default fallback | Ordinary missing Unicode characters | CSS deliberately excludes PUA from installed fallback. It cannot be relied on for U+F8FF. |
| Browser preference | Browser defaults and some non-PUA fallback | Gecko skips preference fallback for PUA. A preference is not a portable repair. |
| User stylesheet or extension | A known site or selector, when the rule adds a named provider | Precise and effective for a page the user controls, but brittle across sites and still cannot repair inaccessible UI or generic-only declarations without winning the CSS cascade. |
| Fontconfig alias or pattern rule | Native and browser clients that pass the named family request through Fontconfig | Linux-specific and implementation-dependent. An alias can reorder a named family; a broad pattern append can affect every request. Use a weak append only with a provider whose PUA mapping is intentionally trusted. |
| Explicit provider font in page CSS | A project's own icon or legacy PUA protocol | The most correct author-side solution. It carries the mapping and metrics with the content, but cannot repair third-party text the user does not control. |
| Patch glyphs into every normal font | A constrained terminal or app font stack | Can make PUA coverage appear universal, but risks collisions because each PUA convention can assign a different glyph to the same code point. Chromium Secure Shell instead keeps a separate, paired provider. |

## Local observations

These observations come from the repository state under review, not from the linked upstream sources.

- [`private-use-fallback.conf.in`](../modules/shared/fonts/private-use-fallback.conf.in) is rendered through [`fontconfig.nix`](../modules/shared/fonts/fontconfig.nix). A generated include contains exact-first-family rules for the font families actually installed in the profile; it excludes the compatibility/protocol namespace and CSS generic names. A separate catalog-driven Apple Color Emoji compatibility gate keeps the known provider behind that protocol family without making it a generic fallback.
- [`private-use-family-aliases.sh.in`](../modules/shared/fonts/private-use-family-aliases.sh.in) is rendered with `replaceVarsWith` and scans selected package directories with `fc-scan`; no website or Stylix family is hardcoded into the generated policy.
- [`default.nix`](../modules/shared/fonts/default.nix) installs the same generated rules through NixOS's system Fontconfig package and Linux Home Manager's user configuration. The Darwin branches install native fonts only and do not configure Linux Fontconfig matching.
- [`fonts.nix`](../flake/dev/fonts.nix) includes the selected providers and rules in isolated Linux Fontconfig test configurations. It runs the PUA, missing-first-family, Apple-stack, Apple-protocol, multilingual, and compatibility browser suites.
- [`check_font_rendering.py`](../tests/browsers/check_font_rendering.py) compares four visible legacy Apple assignments, U+F802, U+F803, U+F804, and U+F8FF, rendered from a named `Roboto, Arial, sans-serif` stack against explicit `Lucida Grande` references. It checks visible ink, raster dimensions, and a bounded pixel difference. This is a focused regression test for the claimed named-stack behavior, not a proof of every PUA value, font style, browser, or operating system.
- [`fonts.nix`](../hosts/nixos/desktop/local/fonts.nix) installs the consolidated Apple font catalog once through the system font directory. Local catalog evidence says it already supplies `Lucida Grande`.
- [`font-config-upstream-guidance.md`](font-config-upstream-guidance.md) already recommends preserving explicit families and using weak binding where language matching should still influence selection. The new rule follows that direction, although the PUA-specific CSS constraint needs its own statement.

The available local evidence identifies U+F8FF as the missing Apple-logo code point. The broad append reproduced the reported App Store regression: the page's `SF Pro` face was not loaded and its Apple stack measured like explicit Lucida Grande. The generated installed-family rules keep the page-owned SF Pro face ahead of the final generic fallback, preserve the four tested visible assignments in Firefox/Zen, and prevent the YouTube-style missing first family from selecting Lucida for ordinary text. Generic-only and Apple platform protocol requests remain outside the compatibility append. Focused font checks and the desktop build passed. Activation is not confirmed because it requires the user's sudo password.

## Recommendation and limits

The constrained design is safe and general enough for this repository's stated
goal: make visible legacy Apple compatibility assignments work in third-party
title strings that name ordinary font families. It is deliberately less invasive
than a strong substitution, a generic alias preference, or a browser-specific
stylesheet. Keep the provider package and Fontconfig rule coupled. Removing the
provider would make the rule inert, and replacing it with a broad symbol font
would create PUA-collision risk.

The boundary is intentional. The browser's private-use fallback request did not
carry a usable `charset` predicate to Fontconfig, so a charset-only rule fixed
ordinary selection but lost the icon repair. A family-level rule is therefore
needed for this browser integration, but it must be bounded by the installed
family inventory and must not rewrite generic or Apple platform protocol
requests. The exact App Store-style stack and a synthetic missing-family stack
are tested together so future compatibility additions cannot reintroduce the
Lucida ordinary-text regression.

Do not broaden the rule into a claim of universal PUA fallback. A PUA value identifies a glyph only within its originating font or protocol. For any additional PUA problem, first identify the originating font and mapping. Prefer a page-owned `@font-face` or a narrowly targeted user stylesheet when the content owner or selector is known. Add another system provider only when the mapping is stable, licensed for installation, and worth applying to unrelated applications.

The concrete maintenance requirements are to retain the limitation near this rule, keep generic-only CSS and browser UI that bypasses Fontconfig out of the guarantee, and keep the provider package coupled to the rule. Future changes should extend the browser test with a Chromium-family run when that browser is available in the validation environment, and keep the existing CJK regression check beside it.

## Validation and limits

This note reviewed the working-tree implementation and primary sources retrieved on 2026-09-16 and 2026-09-17. The old broad configuration failed the missing-first-family and Apple-stack browser regressions; the generated installed-family configuration passes the browser, native, and selection checks. `just os-build desktop` remains the host-level check for the final combined change. Activation is not confirmed because it requires the user's sudo password. The upstream CSS reference is a living draft retrieved on those dates. Chromium-family rendering was not available in this validation environment.
