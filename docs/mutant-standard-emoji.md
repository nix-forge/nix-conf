# Mutant Standard Emoji and the bitmap test rows

Investigated on 2026-09-06 in Zen on the desktop.

The three CBDT/CBLC rows in April93/EmojiTest load the website's own Noto,
EmojiOne Android, and JoyPixels files. Zen rejects each with `no supported glyph
data table(s) present` followed by `rejected by sanitizer`. The page then paints
its Symbola fallback in pink. Those rows do not test the installed fonts. In
the same browser run, the installed Noto Color Emoji, EmojiOne, and JoyPixels
all render the sample faces in color. Installing another font cannot change
the downloaded files or this format compatibility result.

Mozilla's `gfx.downloadable_fonts.keep_color_bitmaps` defaults to false. Its
source describes enabling it as retaining bitmap tables while bypassing OTS
for those tables. It is not necessary for the new COLRv1 font and was not
enabled to make the historical test rows pass.
[Mozilla preference source](https://github.com/mozilla-firefox/firefox/blob/main/modules/libpref/init/StaticPrefList.yaml).

The old Mutant Standard sbix web font is a separate failure: its downloaded
file lacks the required `post` table. Browser font-validation settings remain
unchanged. The original page's web-font result is still 4/8.

Sources: [original test page](https://github.com/April93/EmojiTest/tree/ccd4ff0437bb9d519846c0cfd1bf9ab06a18a018),
[current Mutant Standard downloads](https://mutant.tech/download/all/),
[upstream font-build notes](https://github.com/mutantstandard/build#fonts),
[nanoemoji](https://github.com/googlefonts/nanoemoji).

## Current font build

The user subsequently requested Mutant Standard explicitly, superseding the
earlier decision to leave it absent. `mutant-standard-emoji` in nixpkgs-personal
compiles the official 2024.06 codepoint SVG archive with upstream nixpkgs'
nanoemoji 0.16.0. The resulting family is `Mutant Standard Emoji`, in COLRv1
format. This avoids depending on the discontinued Forc compiler and preserves
vector artwork at different text sizes.

The source archive and SHA-256 hash are pinned in `source.nix`. The package
converts explicit SVG pixel lengths to equivalent unitless coordinates because
picosvg requires them, then compiles the artwork. It preserves all 7,829 supplied
encodings. The historical upstream font alias file is not used: it references
a former private-use transgender-flag encoding that is absent from the current
archive, whose Unicode transgender-flag sequence already has its own artwork.

The font and accompanying documentation credit Caius Nocturne and retain the
CC BY-NC-SA 4.0 license notice and upstream design credits. It is a font build
maintained in nixpkgs-personal, not an official upstream font release.

The shared optional-font module selects the package alongside Firefox Emoji
and EmojiOne. It uses the existing managed font directory and cache-refresh
hook. No family aliases or default-font overrides are added. Noto remains the
normal emoji font. Mutant Standard intentionally has different coverage from
Unicode and includes its own Private Use Area encodings. Artwork without a
codepoint cannot be used as text through a font.

## Validation

A freshly compiled sample loaded as a web font in visible Zen with normal
font validation. A visual comparison against the source SVGs matched the
fourteen face designs and their colors. This validates the new font format,
not the historical test page's sbix download.

The package's install check requires every supplied encoding to shape through
HarfBuzz to one non-missing glyph with a positive advance and a COLRv1 paint
record. This covers ordinary characters, variation selectors, joined
sequences, and private-use modifiers. It does not claim that this optional
artwork set covers every Unicode emoji.

The full browser comparison initially exposed a gap in direct shaping tests:
1,268 sequences had the wrong width in Zen, including a paw-hand sequence that
split into a normal hand and two modifier symbols. Nanoemoji had represented
FE0F as an ordinary ligature component and left some base cmap entries blank.
The final encoding pass maps base characters to their existing artwork, adds
cmap format 14 variation sequences, and rebuilds composition rules without
FE0F. It applies to the whole set and rejects ambiguous normalized encodings.
No glyph artwork or custom character assignment is changed.

Final results:

- Native Nix package build and both 7,829-encoding install checks passed.
- Zen web-font regression: 7,829/7,829 sequences match the expected advance.
- Zen installed-font regression: 7,829/7,829 sequences match the expected advance.
- Original EmojiTest local rows: 8/9 render in color, including Mutant Standard.
  Apple Color Emoji remains absent. The web-font rows remain 4/8.
- All 13 probed existing Fontconfig selections are unchanged.
- Default Noto coverage: 3,953/3,953 Unicode 17 RGI entries.
- Browser numeric regression after installation: 160/160 digits.
- Personal flake evaluation passed on x86_64-linux, aarch64-linux, and
  aarch64-darwin. Only x86_64-linux was built and visually tested here.

The page's optional `local("Mutant Standard Emoji")` diagnostic is false
because the font's full face name is `Mutant Standard Emoji Regular`. Its CSS
family selection visibly renders Mutant Standard correctly. OpenMoji has a
similar exact-face diagnostic distinction. Color rendering and actual family
selection determine the local-row result; the font is not renamed to change
that diagnostic.

The generated managed font and documentation links are applied under
`~/.local/share`, with a targeted font-cache refresh. The declarations preserve
them on future Home Manager activation. Existing browsers may need a restart
to refresh their font lists. Select `Mutant Standard Emoji` in applications
that offer a font chooser and support COLRv1. Noto remains the default.

Evidence: [installed font](assets/mutant-emoji/installed.png),
[comparison with SVG artwork](assets/mutant-emoji/source-comparison.png),
[browser regression](assets/mutant-emoji/browser-results.json),
[pre-fix failures](assets/mutant-emoji/before-summary.json),
[original page results](assets/mutant-emoji/emojitest-results.json).

Run the browser regression with Python containing Selenium, Pillow, and
uharfbuzz, an installed Zen binary, and geckodriver:

```sh
python tests/browsers/check_mutant_emoji.py \
  --font /path/to/MutantStandardEmoji.ttf \
  --artwork /path/to/extracted-codepoint-archive/emoji \
  --browser "$(command -v zen-beta)" \
  --geckodriver "$(command -v geckodriver)" \
  --headed --output /tmp/mutant-browser-check
```

Add `--installed` to test the installed family instead of loading the TTF as a
web font. The SVG archive must be the pinned 2024.06 release. Font validation
is left at the browser's defaults in both modes.
