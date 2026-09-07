# Optional emoji fonts

Follow-up: the user later explicitly requested Mutant Standard. It is now
built from the current artwork in nixpkgs-personal and installed as an optional
font. See [the build and browser validation](mutant-standard-emoji.md). The
initial exclusion discussed below describes the earlier decision.

Reviewed 2026-09-06 against the original [April93 EmojiTest page](https://github.com/April93/EmojiTest/blob/ccd4ff0437bb9d519846c0cfd1bf9ab06a18a018/index.html). This research identifies candidates; the implementation and browser tests determine whether to install them.

| Requested local family | Upstream candidate | Recommendation |
| --- | --- | --- |
| Firefox Emoji | Mozilla FxEmojis `dist/FirefoxEmoji/FirefoxEmoji.ttf`, COLR/CPAL | Test as an optional named font, preserving the default Noto fallback. |
| EmojiOne | EmojiOne 2.2.7 `assets/fonts/emojione-svg.otf`, SVG OpenType | Test the actual original family with attribution. Do not use a differently named font or ship upstream default-changing Fontconfig rules. |
| Mutant Standard Emoji | Current project publishes image packages; font tooling is discontinued | Leave absent under the user's no-compromises condition. A custom legacy font build and noncommercial restrictions add costs without improving standard coverage. |
| Apple Color Emoji | Proprietary Apple system font | Leave absent. No official distributable Linux package was found. |

## Firefox Emoji

Mozilla's repository distributes the actual `Firefox Emoji` font. Pin revision `270af343bee346d8221f87806d2b1eee0438431a`; the upstream font is 1,137,116 bytes. The latest repository commit is dated 2019-03-29 and adds a code of conduct, so this is a historical compatibility font rather than a current Unicode coverage source. The project identifies it as the former Firefox OS set. [Repository](https://github.com/mozilla/fxemoji), [pinned font directory](https://github.com/mozilla/fxemoji/tree/270af343bee346d8221f87806d2b1eee0438431a/dist/FirefoxEmoji), [commit](https://github.com/mozilla/fxemoji/commit/270af343bee346d8221f87806d2b1eee0438431a)

Mozilla licenses the code under Apache 2.0 and the visual designs under CC BY 4.0. Preserve the license and credit Mozilla Foundation. [License](https://github.com/mozilla/fxemoji/blob/270af343bee346d8221f87806d2b1eee0438431a/LICENSE.md)

The earlier test page's Firefox file declares family and full name `Firefox Emoji`, has COLR/CPAL outlines, and contains no printable ASCII mappings. Those facts make it a plausible optional family; they do not establish that every glyph is correct in every application.

## EmojiOne

The official `joypixels/emojione` repository retains tag `v2.2.7`, resolving to `0aad7f9f7969f0187e4f50d12fdc113541a34ac3`. Its fonts directory contains `emojione-svg.otf` (4,226,328 bytes), `emojione-android.ttf` and `emojione-apple.ttf`. The SVG file in April93's test declares the exact family `EmojiOne` and PostScript name `EmojiOneColor`. [Pinned upstream fonts](https://github.com/joypixels/emojione/tree/0aad7f9f7969f0187e4f50d12fdc113541a34ac3/assets/fonts)

The pinned license covers artwork and adaptations with CC BY 4.0 and other material with MIT. Preserve the license and credit EmojiOne. This older grant is distinct from later product licensing. [Pinned license](https://github.com/joypixels/emojione/blob/0aad7f9f7969f0187e4f50d12fdc113541a34ac3/LICENSE.md)

This is an archived font, not a maintained replacement for Noto. The official project says version 2 is unsupported. The separate `13rac1/emojione-color-font` project is also end of life; its Linux installation changes normal default fonts, so its installer and Fontconfig rules are inappropriate for this repair. [EmojiOne status](https://github.com/joypixels/emojione), [SVG font project and Linux installation warning](https://github.com/13rac1/emojione-color-font#install-on-linux)

The test file maps bare digits, number sign and asterisk for keycap sequences. Test ordinary numeric rendering explicitly and avoid prioritizing it over text fonts. Installing the local family cannot repair the older CBDT web font served by an unrelated website.

## Mutant Standard and Apple

Mutant Standard's latest download page offers version 2024.06 as image packages. The build repository says the author stopped developing font technology; custom font compilation uses Orxporter and Forc. Artwork is CC BY-NC-SA 4.0, and the FAQ says no commercial license is available. These restrictions and the custom build requirement do not fit a general system addition without compromises. [Downloads](https://mutant.tech/download), [font build instructions](https://github.com/mutantstandard/build#fonts), [licensing FAQ](https://mutant.tech/about/faq)

Apple's current macOS Tahoe agreement, section 2E, permits use of included fonts while running Apple Software and separately limits embedding. It does not provide an ordinary Linux redistribution grant. Do not obtain a copy from an unofficial font mirror or rename another font to impersonate Apple Color Emoji. [Apple agreement](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf)

## Nixpkgs and validation boundary

The pinned Nixpkgs source was searched for these font packages. No usable Firefox Emoji or Mutant Standard font package was found. Its `emojione` compatibility alias throws an error, recording removal on 2025-11-06 because upstream was archived. Exact original-font installation therefore requires small pinned derivations with license notices rather than enabling a current Nixpkgs package.

Keep the existing Unicode 17 Noto default and browser sanitizer settings. Any optional installation should pass the original named-family rows, numeric rendering, default emoji coverage, fallback-selection comparisons and font-console checks. Rejecting the historical website's invalid web-font files remains correct behavior; neither a local font installation nor a fake alias changes those files.

## Installed and verified

Both candidates passed testing and are now installed for the desktop Linux user through `modules/home/desktop/optional-emoji-fonts.nix`, imported by `homes/desktop/default.nix`. The derivation pins upstream revisions and SHA-256 hashes, copies only the two unchanged fonts, and installs upstream license files and attribution. It adds about 5.4 MB of font data. It introduces no Fontconfig aliases, installers, browser preferences, or defaults.

The actual upstream files are byte-identical to the corresponding files in the pinned EmojiTest page. Firefox Emoji declares version 1.7.9 and uses COLR/CPAL. EmojiOne comes from release 2.2.7 and uses SVG OpenType with its authentic `EmojiOne` family name.

In a fresh visible Zen window using the live user configuration, the original page now renders **7/9 local families in color**, up from 5/9. Firefox Emoji and EmojiOne pass alongside the five previously working families. Apple Color Emoji and Mutant Standard Emoji remain absent for the reasons above. The exact-face `local("OpenMoji")` diagnostic remains false while the page's CSS family alias visibly renders OpenMoji correctly, so it is counted as a pass.

The original website's web-font result stays **4/8**. Its three CBDT files and malformed Mutant sbix file still fail normal browser validation. Installing local fonts does not change those downloads. The browser sanitizer and its bitmap-table preference were not changed.

A trial Fontconfig configuration pointing at font files directly under `/tmp` found the family names but rendered the local rows with Symbola fallback. Retesting the same bytes in their built Nix store location resolved that failure without changing browser security settings. Final verification used normal live XDG font discovery, with no custom `FONTCONFIG_FILE`.

Validation preserved the selected files for Inter, Literata, MonaspiceNe, default emoji, Arial, Roboto, and the pre-existing symbol fallback probes. Noto Color Emoji remains the default and passes all 3,953 Unicode 17 RGI shaping checks. Ghostty still selects the text Noto Emoji face for the bare stopwatch. The original 160-digit browser regression passed with the candidate fonts, and was repeated after live installation. The original page showed the same expected web-font sanitizer diagnostics and no new font-file failures.

The Home Manager files derivation built successfully, and normal Git-flake evaluation, Nix formatting, and whitespace validation passed. Only these two generated links were applied to the live user profile:

- `~/.local/share/fonts/optional-emoji`
- `~/.local/share/doc/optional-emoji-fonts`

The Nix declarations preserve them on subsequent Home Manager activation. A targeted cache refresh covered the new font directory. Restart existing browsers to refresh their cached font lists; no system rebuild is needed to use the fonts now.

Evidence: [full test page](assets/optional-emoji/emojitest.png), [EmojiOne](assets/optional-emoji/emojione.png), [Firefox Emoji](assets/optional-emoji/firefox-emoji.png), [row diagnostics](assets/optional-emoji/results.json).

These are optional historical designs, not a promise of current Unicode coverage in each family. No regression was found in the tested defaults, numeric text, emoji coverage, or stopwatch. Their roughly 5.4 MB disk cost and normal attribution obligations remain; no installation can promise zero cost or zero risk in every application.

## Migration to nixpkgs-personal

The font derivations now live in the personal package repository:

- `pkgs/pkgs/by-name/fi/firefox-emoji`, version 1.7.9.
- `pkgs/pkgs/by-name/em/emojione-legacy`, release 2.2.7.

Each is a standalone `stdenvNoCC` package with a separate pinned `source.nix`, accurate licenses and homepage metadata, standard `share/fonts/truetype` or `share/fonts/opentype` installation, and attribution under `share/doc`. Both are exported through the personal flake and overlay. No upstream installers or Fontconfig aliases are included.

Install checks verify the exact upstream bytes, Fontconfig family identity, the 14 EmojiTest glyphs, and the color data covering those glyphs. Tests use a private minimal Fontconfig configuration and writable temporary cache, so they do not depend on host fonts or host configuration. Firefox's old source contains two extra bytes in `post.stringData`; FontTools reports that metadata warning, and the source remains unmodified. Its glyph/color checks and actual browser rendering pass.

Both package checks built on x86_64-linux. `nix flake check --all-systems --no-build` passed for the personal flake, including evaluation of the two checks on aarch64-linux and aarch64-darwin. Those two platforms were evaluated, not built on this host. The development partition initially referenced an absent store copy; adding the existing `pkgs/flake/dev` directory to the store restored evaluation without changing dependencies or lock files.

The desktop module now only selects the personal packages and joins their font/documentation directories into the existing XDG links. Both font hashes were checked against the previous installation before migrating those links. Fontconfig's old cache retained the former flat file paths because Nix directories share timestamps. A targeted forced refresh repaired it, and the module's `onChange` hook now performs that refresh on future link changes. The live font selections point to existing files in `truetype` and `opentype`.

These packages deliberately have no automatic updater. Firefox Emoji is historical, and updating EmojiOne past release 2 would require a new license and artwork review. The personal repository README documents this maintenance policy and the build commands.
