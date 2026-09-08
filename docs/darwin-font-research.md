# Darwin font audit

Research date: 2026-09-06. This note checks how the earlier Linux font repairs apply to macOS. It separates source-backed behavior from results that still require a Mac.

## Native installation

The pinned nix-darwin font module installs `fonts.packages` into `/Library/Fonts/Nix Fonts`. It gathers TTF, TTC, OTF, and dfont files, then copies their contents during activation with `rsync --copy-links`. Its managed directory uses the original store paths so activation can distinguish package versions and delete obsolete managed copies. [Pinned nix-darwin source](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/fonts/default.nix).

The pinned Home Manager Darwin target already installs fonts from `home.packages`. It builds a font directory and copies the files into `~/Library/Fonts/HomeManager`, using checksums, dereferencing symlinks, and deleting obsolete files in that managed directory. Its source explicitly explains that macOS does not recognize symlinked fonts. Adding a separate symlink under `~/Library/Fonts` would bypass this existing mechanism. [Pinned Home Manager source](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/fonts.nix).

At the start of this audit, `modules/home/desktop/optional-emoji-fonts.nix` installed Firefox Emoji and EmojiOne only through a Linux-guarded XDG data directory. On Darwin it installed neither font. The appropriate repair is to add those existing packages to `home.packages` on Darwin and let Home Manager perform the native installation. Keep the existing Linux path to avoid introducing another copy there.

Both personal packages already use standard font directories, preserve upstream font bytes, include license and attribution documents, and declare `lib.platforms.all`. Their install checks inspect cmap coverage and color tables. These properties support Darwin packaging but do not establish successful native rendering or prove that the derivations build on Darwin.

## Duplicate Noto Color Emoji

The earlier Linux repair rejects the Google Fonts copies of `NotoColorEmoji-Regular.ttf` and `NotoColorEmojiCompatTest-Regular.ttf` through Fontconfig. Core Text provides its own font handling and cascading. A Fontconfig reject rule therefore does not remove those files from the native font installation or establish what Core Text selects. [Apple Core Text documentation](https://developer.apple.com/documentation/CoreText), [Home Manager Fontconfig module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/fontconfig.nix).

The earlier local audit established that the Google Fonts bundle contains Noto Color Emoji 2.048 while the dedicated package contains 2.051, with the same identifying font names. The older face lacks 148 tested Unicode 17 emoji sequences. Those are observations from this repository's Linux audit, not measurements of Core Text selection. [Earlier audit](system-font-audit-research.md).

Remove the two conflicting files from the installed Google Fonts package on both platforms. Apply the filtered package to every managed font path that can install the bundle, including Stylix's Literata package and the shared font collection. Keep the Linux reject rule as protection against old profiles. On Darwin, allow the existing Nix and Home Manager activation scripts to remove their old managed copies. Do not delete unrelated user fonts or Apple system fonts. Font Book can validate manually installed fonts and identify duplicate versions if a Mac still reports conflicts. [Apple Font Book validation guide](https://support.apple.com/en-au/guide/font-book/fntbk1000/mac).

## Ghostty fallback

Ghostty's documentation states that its default emoji family is Apple Color Emoji on macOS. An explicit `font-family` containing emoji glyphs overrides that selection. Ghostty also documents Core Text as the macOS font backend. [Ghostty option reference](https://ghostty.org/docs/config/reference#font-family).

The pinned Stylix Ghostty target sets `font-family` to both the configured monospace family and configured emoji family. Here the latter is Noto Color Emoji. The existing primary-family-only override was inside the Linux branch, so the Darwin configuration still forced Noto ahead of Ghostty's native emoji choice. [Pinned Stylix target](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/ghostty/hm.nix).

Apply the primary-family-only override on both systems. That preserves MonaspiceNe text while returning emoji selection to Ghostty. This is a direct configuration correction on macOS; the precise stopwatch pixel size still needs a native screenshot and should not be inferred from the Linux result.

## Optional color formats

Firefox Emoji uses COLR version 0 with CPAL palettes. EmojiOne Legacy uses SVG-in-OpenType. Gecko's common font code explicitly renders SVG and COLR glyphs, and its macOS implementation participates in the same color-font machinery. This supports testing those fonts in Firefox or Zen on macOS without disabling downloadable-font validation. It is source evidence for the rendering paths, not a completed test of these exact files on macOS. [Gecko glyph rendering](https://github.com/mozilla-firefox/firefox/blob/main/gfx/thebes/gfxFont.cpp), [Gecko font-table handling](https://github.com/mozilla-firefox/firefox/blob/main/gfx/thebes/gfxFontEntry.cpp), [Gecko macOS implementation](https://github.com/mozilla-firefox/firefox/blob/main/gfx/thebes/gfxMacFont.cpp).

WebKit documents COLRv0 support, but that does not prove that both historical fonts render in every current native application. In particular, do not infer system-wide SVG-in-OpenType support from a successful Gecko test. Keep both optional families available for explicit selection, outside general text and default emoji fallback lists. [WebKit color-font documentation](https://webkit.org/blog/12662/customizing-color-fonts-on-the-web/).

Apple Color Emoji already belongs to Apple's macOS font collection. The earlier decision not to redistribute it on Linux does not mean it should be removed or bypassed on a Mac. [Apple system-font list](https://developer.apple.com/fonts/system-fonts/).

## Validation boundaries

Evaluate the Darwin system and Home Manager outputs to verify package inclusion, native font activation paths, the filtered Google Fonts package, and Ghostty's final `font-family`. Build the two personal font derivations on Darwin when a builder is available. Those checks establish packaging and configuration only.

After activation on a Mac, inspect the native font collection and restart an isolated Zen or Firefox instance. Repeat the 160-digit test, the EmojiTest local rows, and a screenshot of the stopwatch with both text and emoji presentation. Check native Apple emoji fallback separately from the explicit Noto Unicode 17 coverage test. A Linux `fc-match` result, a successful evaluation, or font-table inspection cannot substitute for those native rendering checks.

## Changes and completed checks

The shared Google Fonts override now removes both conflicting emoji files at installation time. Shared fonts, Stylix, and the legacy NixOS font module all use that override. The upstream package's custom `installPhase` does not invoke `postInstall`, so the removal is appended to `installPhase` itself. The Linux rejection rules remain useful for older profiles.

The MacBook Home Manager configuration now imports the optional font module. On Darwin it adds the existing `firefox-emoji` and `emojione-legacy` personal packages to `home.packages`. Evaluation confirms that Home Manager copies the resulting font collection into `/Users/ianmh/Library/Fonts/HomeManager`, with obsolete managed copies deleted during activation. Linux keeps its existing XDG installation and targeted cache refresh.

Ghostty now specifies only `MonaspiceNe Nerd Font` on both systems. This lets Ghostty use its platform emoji fallback. The browser's Fontconfig substitution-limit adjustment remains Linux-only; evaluation confirms that neither Darwin Zen profile receives that preference or an explicit emoji-family override.

Completed on the Linux desktop:

- Built the filtered Google Fonts package. Compared every output file against the original package. Exactly the two unwanted font files were removed, and all 3,845 remaining files were byte-identical. Literata remains present.
- Evaluated the complete `darwinConfigurations.macbook-pro-m4.system.drvPath` successfully. This evaluates the Darwin system derivation; it does not build or activate macOS.
- Evaluated both platforms' effective font settings. Every configured Google Fonts entry in each system and Home Manager uses its platform's same filtered package. Both Ghostty configurations contain only the chosen monospace family. The Darwin home package list includes both optional emoji fonts.
- Checked Nix formatting and patch whitespace.

The configured `Ian-MBP.local` hostname did not resolve from the desktop. No Darwin activation, native font log inspection, or Mac rendering test was performed. Apply the configuration on the Mac with `just darwin-switch macbook-pro-m4`, then verify the native rendering cases above. The older Fontconfig-only repair did not establish Darwin correctness, and these configuration checks do not claim that every macOS application supports SVG-in-OpenType.
