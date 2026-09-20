# Cross-platform font compatibility research

Reviewed: 2026-09-17. Scope: the Linux NixOS, macOS nix-darwin, and Home Manager font paths in this repository. Upstream source revisions are the revisions locked in `flake.lock`: Nixpkgs `c5c4a43b0e8056328ec4529f735cabdb8f1942bb`, Home Manager `f10b3f2ad4aae9259617a1ff518cc921e3394228`, nix-darwin `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`, and Stylix `5e3809851f486e7fc7e84b40f174c74b60ecc784`.

## Answer

Use one portable catalog of named roles, package providers, sizes, and script or emoji fallback requirements. Keep the mechanisms that interpret those roles platform-specific.

- Stylix should remain the shared role layer: `sansSerif`, `serif`, `monospace`, `emoji`, and sizes. It is a configuration contract for themed targets, not a portable operating-system system-font API.
- On Linux, NixOS should own the host-wide font inventory and Fontconfig fallback policy. Home Manager should add user inventory and user Fontconfig configuration only when user-installed fonts or per-user overrides require it. The same Linux policy may be rendered in both scopes when both scopes need the fonts, but it should come from one renderer and have one ordering contract.
- On macOS, nix-darwin should install genuinely shared document fonts and Home Manager should install a user's role fonts. Native applications resolve system faces and fallback through Core Text. Do not treat Fontconfig aliases as a way to change the macOS system font or Core Text cascading.
- Keep `-apple-system` and `BlinkMacSystemFont` handling as a Linux-only, narrowly tested web-compatibility boundary. Do not turn either identifier into the shared Stylix sans meaning; leave them available for later page-owned families and use CSS generic mappings only for actual generic keywords. Web authors who need a particular face should ship a licensed web font or use the portable CSS generic.

This is the smallest architecture that gives repository-owned applications a stable role name without claiming that Inter, Literata, MonaspiceNe, or Noto Color Emoji are identical to the operating system's UI faces on both platforms.

## Documented facts

### CSS and web fonts

**Fact.** CSS `font-family` is an ordered list of family names and generic-family keywords. A generic family is an alias for an installed family or a composite face that may vary with Unicode range, language, user preferences, and system settings. `system-ui`, `ui-sans-serif`, `ui-serif`, `ui-monospace`, and `ui-rounded` are generic keywords, not names for one portable font file. [CSS Fonts Level 4, font-family and generic families](https://www.w3.org/TR/css-fonts-4/#font-family-prop).

**Fact.** `system-ui` is the CSS system-font generic. It asks for the platform's default UI font and, unlike a named family, permits the platform's locale and user-preference behavior. [CSS Fonts Level 4, system fonts](https://www.w3.org/TR/css-fonts-4/#system-font-def).

**Fact.** A document-owned `@font-face` can share a family name with an installed face. CSS treats web fonts as document-scoped and uses them in preference to installed faces with the same family name in that document. `local()` is a separate source lookup and matches a local face name, not a general platform alias. [CSS Fonts Level 4, font taxonomy](https://www.w3.org/TR/css-fonts-4/#font-taxonomy) and [local font fallback](https://www.w3.org/TR/css-fonts-4/#local-font-fallback).

**Fact.** A fallback font can change text width, line boxes, and wrapping even when it has all required glyphs. CSS supplies metric overrides for authors who need a fallback to occupy the primary web font's metrics. [CSS Fonts Level 4, font metric overrides](https://www.w3.org/TR/css-fonts-4/#font-metrics-override-desc).

### Linux and Fontconfig

**Fact.** Fontconfig configuration rules act on a request pattern or the selected font pattern. `target="pattern"` edits happen before matching; family edits and bindings change the candidates considered by matching. Configuration order matters. [Fontconfig configuration and matching](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#match) and [edit operations](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#edit).

**Fact.** NixOS registers `fonts.packages` as Fontconfig directories, produces a Fontconfig cache, and generates default aliases at priority 52. Its `defaultFonts` lists are `<prefer>` candidates with `binding="same"`, for `sans-serif`, `serif`, `monospace`, and `emoji`. [Pinned NixOS Fontconfig module](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/nixos/modules/config/fonts/fontconfig.nix).

**Fact.** Home Manager discovers fonts from its profile and `home.packages`, writes its Fontconfig configuration below the XDG configuration directory, and generates the same four default aliases at priority 52. Its custom `configFile` priority range is 0 through 99. [Pinned Home Manager Fontconfig module](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/misc/fontconfig.nix).

### macOS and Core Text

**Fact.** Apple calls San Francisco its system typeface. Apple also documents `-apple-system` as WebKit's CSS route to San Francisco and calls `system-ui` the standard CSS name. That describes Apple-platform behavior, not a promise that either name selects San Francisco on Linux. [Apple typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography) and [WWDC20: The details of UI typography](https://developer.apple.com/videos/play/wwdc2020/10175/).

**Fact.** Core Text has an API to obtain the UI font for a chosen UI use and language. Core Text also supplies automatic font cascading, based on system and font-specific cascade lists, to choose fonts for missing characters while considering traits. [CTFontCreateUIFontForLanguage](https://developer.apple.com/documentation/coretext/ctfontcreateuifontforlanguage(_:_:_:)) and [Core Text overview](https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/CoreText_Programming/Overview/Overview.html).

**Fact.** nix-darwin installs `fonts.packages` in `/Library/Fonts/Nix Fonts` during activation. Home Manager's Darwin target collects fonts from `home.packages`, copies them into `~/Library/Fonts/HomeManager`, and explicitly avoids symlinks because macOS does not recognize symlinked fonts. [Pinned nix-darwin font module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/fonts/default.nix) and [pinned Home Manager Darwin font target](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/targets/darwin/fonts.nix).

### Stylix

**Fact.** Stylix defines four font roles, each with a package and family name, plus role-oriented sizes. When enabled, it derives `stylix.fonts.packages` from those four packages. Its Fontconfig target writes the four NixOS or Home Manager default-font lists from the corresponding role names. [Pinned Stylix font options](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/stylix/fonts.nix), [Fontconfig target](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/fontconfig/fontconfig.nix), and [font-package targets](https://github.com/nix-community/stylix/tree/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/font-packages).

## Repository observations

These are observations of the working tree, not upstream guarantees.

| Area | Current behavior | Cross-platform reading |
| --- | --- | --- |
| [`modules/shared/fonts/packages.nix`](../modules/shared/fonts/packages.nix) | Defines Inter, Literata, MonaspiceNe Nerd Font, and Noto Color Emoji as the four roles. It also separately names Apple compatibility identifiers. | This is the right separation. The role catalog is portable. Apple identifiers are protocol names, not roles. |
| [`modules/shared/stylix/default.nix`](../modules/shared/stylix/default.nix) | Sets the same Stylix roles on NixOS, Darwin, and Home Manager. Linux adds cursor and icon targets. NixOS and Home Manager force ordered Fontconfig default lists. Darwin disables Stylix's system font-package target. | A shared role selection is sound. The Darwin target disable avoids a second system-level installation of role packages. |
| [`modules/shared/fonts/default.nix`](../modules/shared/fonts/default.nix) | NixOS installs the selected collection system-wide and adds the generated CSS-generic and private-use Fontconfig fragments. Home Manager installs the selected collection in `home.packages` and enables those fragments only on Linux. Darwin gets native nix-darwin document fonts and no generated Fontconfig policy. | The inventory ownership and matching mechanisms are intentionally split on Darwin. Core Text owns native system-face behavior there. |
| [`modules/nixos/stylix-components/fonts.nix`](../modules/nixos/stylix-components/fonts.nix) | Supplies a lower-priority NixOS Stylix role set and Fontconfig defaults. | It is a compatible fallback layer. Its defaults can be superseded by the shared Stylix module, so it should not become a competing role source. |
| [`flake/dev/fonts.nix`](../flake/dev/fonts.nix) | Builds isolated Fontconfig configurations, checks role selection and emoji coverage, and runs Linux browser and native rendering checks. It deliberately notes that collection isolation is Fontconfig-specific and that Core Text needs a separate check after activation. | This is good Linux evidence. It does not validate macOS Core Text selection, font cascading, or system UI metrics. |

The Linux CSS-generic template strongly prepends the active Stylix role for
`system-ui` and the `ui-*` generic requests. Apple platform protocol names
(`-apple-system*` and `BlinkMacSystemFont`) are intentionally left unresolved
so a page can continue to its later named/webfont entries. The private-use
template includes generated weak exact-first-family rules only for installed
named families, plus a catalog-driven Apple Color Emoji compatibility gate.
See [`css-generic-alias.conf.in`](../modules/shared/fonts/css-generic-alias.conf.in),
[`private-use-fallback.conf.in`](../modules/shared/fonts/private-use-fallback.conf.in),
and [`private-use-family-aliases.sh.in`](../modules/shared/fonts/private-use-family-aliases.sh.in).

## Inferences and recommended architecture

**Inference.** Keep the role catalog and role-to-application target mapping cross-platform. Those are repository policy. Keep matching, fallback, font installation ownership, and system aliases in an operating-system adapter. Those depend on Fontconfig on Linux and Core Text on macOS.

**Inference.** The current NixOS and Home Manager default lists should be generated from the same `catalog.fallbacks` function, as they are now. On Linux that makes a user application and a system service start with the same ordered policy. The duplicate package declarations deserve an inventory audit, but not a blind deduplication: NixOS packages are visible to host services, whereas Home Manager packages are needed for a standalone user profile and native Darwin installation.

**Inference.** Gate the three custom Fontconfig fragments to Linux unless there is a named Fontconfig-using macOS application that needs them. Leaving them enabled on Darwin is not necessarily harmful to such applications, but it gives no Core Text guarantee and obscures the actual native ownership boundary.

**Inference.** On macOS, preserve Apple system selection for native UI and for browser `system-ui` or `-apple-system` behavior. Apply the selected Stylix role by explicit family name only where the repository owns the application configuration. This preserves user language, accessibility, system text styles, and Apple fallback behavior. The repository now enforces that boundary by omitting the generated Fontconfig fragments and Linux default lists from the Darwin Home Manager branch.

**Inference.** Treat the Apple protocol names on Linux as a compatibility boundary, not as a font alias. Keep their exact-name regression fixtures beside the generic-role and webfont tests. It should be possible to remove the boundary test without changing the generic-role policy.

## Concrete risks of mapping Apple protocol names to Stylix sans

1. **A substitution can change a named stack before later author fallbacks.** Mapping `-apple-system` to a local Linux role makes that role win before entries such as `SF Pro`, `Helvetica Neue`, `Helvetica`, `Arial`, and `sans-serif`. The Linux adapter therefore leaves the protocol name unresolved; the page-owned provider remains eligible and the final generic still follows the configured role. CSS's metric-override feature exists because these substitutions are not metrically neutral. [CSS metric overrides](https://www.w3.org/TR/css-fonts-4/#font-metrics-override-desc).

2. **It cannot reproduce a macOS UI request.** `-apple-system` on Apple platforms requests San Francisco, while Core Text can select a UI font by use and language and cascade missing glyphs. A Linux Fontconfig rule can supply Inter, but it cannot carry the same text-style, language, cascade, or user-setting behavior. [Apple UI font API](https://developer.apple.com/documentation/coretext/ctfontcreateuifontforlanguage(_:_:_:)) and [Core Text cascading](https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/CoreText_Programming/Overview/Overview.html).

3. **A broad match can affect names outside the intended protocol.** A global private-use append affects a missing first family as well as an installed named family; the browser can then choose the compatibility provider for ordinary text. The generated exact-first-family allowlist gives the rule a build-time boundary without naming websites or selectors. A synthetic missing-family regression protects that boundary.

4. **It can hide a page-owned web-font problem.** A document-scoped `@font-face` may intentionally shadow an installed family. Global system substitution cannot prove that the web font loaded, has the expected weights, or has matching metrics. Test installed, `local()`, and downloaded-face paths separately. [CSS font taxonomy and local fallback](https://www.w3.org/TR/css-fonts-4/#font-taxonomy).

5. **It makes an Apple-specific behavior look like a portable generic default.** `system-ui` is the portable way to request a platform UI font. Mapping Apple protocol names and `system-ui` to the same Stylix sans loses the distinction between "match this Linux desktop's configured role" and "ask the page/platform for its UI face." Keep that distinction visible in the configuration and tests. [CSS system-font definition](https://www.w3.org/TR/css-fonts-4/#system-font-def).

6. **It expands the PUA compatibility surface.** Private-use glyph assignments are not interoperable meanings. The fallback remains limited to the known provider, installed-family rules, the Apple Color Emoji protocol gate, and visible fixtures; it must not become a generic-family fallback. [CSS handling of private-use characters](https://www.w3.org/TR/css-fonts-4/#char-handling-issues).

## Validation and limits

This review inspected the specified files and linked upstream source on 2026-09-17. It did not evaluate, build, activate, or modify the configuration. Existing Linux checks in [`flake/dev/fonts.nix`](../flake/dev/fonts.nix) are useful evidence for Fontconfig, Gecko, Qt, and Pango under their isolated setup. They do not establish native macOS behavior.

Before changing the architecture, validate two separate contracts:

- Linux: evaluate the NixOS and Home Manager outputs, then run the isolated Fontconfig and browser checks with a fresh cache. Assert selected files and rendered metrics for generic requests, Apple protocol names, named stacks, web fonts, CJK fallback, and emoji.
- macOS: evaluate the Darwin and Home Manager outputs, activate on a Mac, then inspect the managed font directories and test a Core Text client plus a browser. Check the selected UI font, fallback for at least one non-Latin script and emoji, and line metrics for an Apple-style stack. A Linux `fc-match` result is not evidence for this path.

## Implication for this repository

The platform adapter boundary is now implemented: shared Stylix roles and
application target values remain above it, Linux Fontconfig policy is rendered
only in the Linux adapter, and native nix-darwin/Home Manager installation plus
Core Text validation remain below the Darwin adapter. Apple protocol names stay
out of the role catalog and are not rewritten into a Linux role; the browser
regression test protects later page-owned families.
