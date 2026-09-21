# Private-use fallback and missing-family regression addendum

Reviewed: 2026-09-17. Scope: whether the global Linux Fontconfig append rendered from the [private-use template](../modules/shared/fonts/private-use-fallback.conf.in) can change ordinary App Store or YouTube text selection, and whether Apple platform protocol names hide later page-owned fonts. This addendum does not repeat the PUA mapping conclusions in [the original research note](private-use-font-fallback-research.md).

## Answer

Yes, but it was only one part of the regression. The original rule matched every Fontconfig request
whose family list lacked `Lucida Grande`, then appended that family before
Fontconfig selected a face. `binding="weak"` reduced its precedence relative to
language, but did not make the edit character-specific or prevent it entering
ordinary requests. On the exact App Store page, the broad rule prevented the
SF Pro webfont from being requested and made the Apple stack measure like
Lucida Grande.

The first attempted constrained append still had an important boundary problem:
Fontconfig cannot tell this pattern rule whether the first CSS family is
actually installed. It could therefore still affect a missing first family such
as YouTube's `YouTube Noto, Roboto, Arial, sans-serif` stack. The final rule is
generated from the selected profile's installed font families and only matches
an exact installed first family. Apple platform protocol names are left
unresolved on Linux so a page-owned SF Pro webfont remains eligible; CSS generic
names continue to use the configured Stylix roles. The generated Linux policy is
not installed in Darwin Home Manager, where Core Text owns native system-font
behavior.

## Source-backed observations

- Apple’s public stylesheet for the specified [App Store page](https://apps.apple.com/ca/app/habi/id6741903553) declares ordinary UI stacks beginning `-apple-system` and containing `SF Pro`, `SF Pro Icons`, `Helvetica Neue`, `Helvetica`, `Arial`, and `sans-serif`. The page also links Apple's WSS stylesheet, which declares the `SF Pro` and `SF Pro Icons` webfaces, including `SFPro.woff2`. The static page stylesheet itself has no SF Pro `@font-face`; its locale-switcher faces are separate. These assets were retrieved on 2026-09-16 from [Apple's static stylesheet](https://apps.apple.com/assets/index~CzDHPOrlII.css) and [Apple's WSS font stylesheet](https://www.apple.com/wss/fonts?families=SF+Pro,v4%7CSF+Pro+Icons,v1&display=swap). They are public, volatile evidence, not a promise about later Apple assets.
- Apple documents SF Pro as its system typeface in the [Typography Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/typography), and its [WWDC typography guidance](https://developer.apple.com/videos/play/wwdc2020/10175/) describes `-apple-system` as the CSS route to San Francisco on Apple platforms. This supports treating the names as platform aliases rather than as ordinary site-specific font families.
- The relevant CSS aliases are not all the same string. Apple pages use `-apple-system`, `BlinkMacSystemFont`, and variants such as `-apple-system-body`; ChatGPT's computed stack begins with `-apple-system-body`. [MDN's `font-family` reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/font-family) describes `system-ui` as the platform UI family, while [MDN's `font` reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/font) records the WebKit `-apple-system-*` names.
- CSS defines `font-family` as an ordered list. The user agent tries alternatives until it finds an available font with the glyph and uses other font properties to choose a face. [CSS Fonts Level 4](https://www.w3.org/TR/css-fonts-4/#font-family-prop) was a 2026-09-13 Working Draft when retrieved.
- Fontconfig says a `target="pattern"` match edits the query pattern, and an edit inserts values with the declared binding. Family bindings are strong or weak. Weak family values rank below language, not outside matching. [Fontconfig 2.18.2 configuration source](https://github.com/fontconfig/fontconfig/blob/2.18.2/doc/fontconfig-user.sgml) matches the installed `fc-match` runtime, which reported version 2.18.2.
- Firefox's Linux Fontconfig integration calls `FcConfigSubstitute` with `FcMatchPattern` before it derives family candidates. The exact source revision retrieved was `6399208a6b0ab89af6a834648e0330367168ccd1`. [Gecko source](https://github.com/mozilla-firefox/firefox/blob/6399208a6b0ab89af6a834648e0330367168ccd1/gfx/thebes/gfxFcPlatformFontList.cpp) is direct evidence that such pattern edits reach Firefox-family selection.
- Locally, `fc-match 'SF Pro:style=Regular'` resolved an installed SF Pro Regular face. A fresh Firefox profile with the broad rule reproduced the exact App Store spacing and a real YouTube page measured its player controls like Lucida Grande even though the page loaded Roboto. This rules out stale browser state and CSS letter spacing as the primary cause: the computed stacks themselves contained an unavailable first family followed by a usable webfont.
- A temporary prefix mapping for `-apple-system*` and an exact mapping for `BlinkMacSystemFont`, both prepending SF Pro with a strong binding, made Apple stacks use the SF Pro metric but could outrank a later named provider. The final configuration therefore does not map those protocol names to Stylix or SF Pro. Leaving them unresolved lets the browser try the document-owned family before the final generic role.
- The compatibility suite now covers exact Apple protocol names, the Apple-style webfont stack, the ChatGPT stack, named-family private-use glyphs, and a synthetic missing-family stack alongside the real YouTube stack shape.
- NixOS installs the rendered package through `fonts.fontconfig.confPackages`, and Linux Home Manager links each `fonts.fontconfig.configFile` entry into the user Fontconfig directory. The repository therefore installs the same generated rules through both Linux paths; Darwin intentionally receives neither alias fragments nor the Linux default lists. [NixOS source at `c5c4a43b`](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/config/fonts/fontconfig.nix) was pinned 2026-08-29. [Home Manager source at `f10b3f2a`](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/misc/fontconfig.nix) was pinned 2026-09-11.

## Safer redesign

Do not retain an unqualified family append. A charset-gated experiment was
also tested, but the browser's private-use fallback request did not expose a
usable character set to the Fontconfig pattern rule: it stopped the PUA repair
in the browser path even though direct `fc-match` probes can exercise charset
predicates. The practical high-quality boundary is therefore a generated
family-stack rule with an installed-family boundary. The rule rendered from the
[`private-use-fallback.conf.in`](../modules/shared/fonts/private-use-fallback.conf.in)
template receives a generated include from
[`private-use-family-aliases.sh.in`](../modules/shared/fonts/private-use-family-aliases.sh.in).
That include contains weak exact-first-family rules only for font families
found in the selected package directories, excludes generic and Apple protocol
names, and therefore leaves an unavailable first family untouched. A small
catalog-driven Apple Color Emoji gate preserves the known private-use provider
behind that protocol family without making it a global fallback.

## Tests required before changing the rule

Run each test with and without the candidate rule, in an isolated Fontconfig configuration containing SF Pro and Lucida Grande.

1. Use a local page with Apple's exact ordinary stack and a representative webface. Confirm that ordinary text does not measure like Lucida Grande and that the page-owned provider wins without a Linux alias shadowing it.
2. Render the tested legacy Apple PUA assignments from a named stack and verify visible ink and agreement with explicit Lucida Grande references.
3. Render an Apple private-use glyph from the named stack and keep Apple protocol-name requests separate from the generic-role test.
4. Check generic-only Fontconfig requests. They must remain on the configured interface, serif, and monospace families rather than resolving to the compatibility provider.
5. Keep the existing CJK and generic-family checks. They catch unintended changes to language fallback, which weak binding does not rule out.

## Validation

The old broad configuration fails the offline `missing-named-stack` suite: both
the YouTube-shaped stack and the synthetic missing-family stack measure like
Lucida despite a later Roboto family. It also fails the Apple-stack suite by
preventing the page-owned webfont from determining ordinary metrics. The
generated installed-family configuration passes the Apple stack, Apple
platform, missing-family, four-case named-family PUA, multilingual, generic,
native, and selection checks. Validation used fresh Firefox/Gecko profiles on
Linux; Chromium-family rendering and native macOS rendering were not available.
Running-system activation still requires the user's privileged activation step.
