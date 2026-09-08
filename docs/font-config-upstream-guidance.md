# Font configuration: upstream guidance

Research date: 2026-09-06. This note supports the repository font review. It records upstream behavior separately from proposed improvements; it does not change the installed configuration. Home Manager, nix-darwin, and Stylix links below use the revisions in the current root lock file. Nixpkgs links marked `master` describe current upstream behavior and should be checked against the package set selected by each host before implementation.

## Module ownership and installation

Home Manager's Fontconfig module discovers profile fonts and bundled configuration, builds a profile cache, and adds that cache to user configuration. Its `defaultFonts` options generate aliases with `binding="same"`. Structured `configFile.settings` is available alongside XML text or an explicit source. This already supplies the normal lifecycle needed by fonts installed through `home.packages`. [Home Manager implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/fontconfig.nix).

The NixOS module registers `fonts.packages` directories and prebuilt caches. Its default-family aliases also use `binding="same"`. It supplies separate switches for embedded bitmaps, bitmap-font selection, Type 1 selection, antialiasing, hinting, and subpixel geometry. These have different effects; combining them into one generic quality switch would obscure what changes. [NixOS implementation](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/fonts/fontconfig.nix).

Stylix's Fontconfig target writes the four default-family lists from its chosen font names. It supports both NixOS and Home Manager. [Pinned Stylix implementation](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/fontconfig/fontconfig.nix).

Recommended design:

- Keep package selection in one shared catalog, with explicit desktop defaults and optional document, language, and alternate emoji collections.
- Give each installed collection one owner per host. Use NixOS for system fonts, or Home Manager for fonts confined to one user; retaining both mechanisms is reasonable when their responsibilities differ.
- Let Stylix own the default families already delegated to it. Add fallback policy in a module that reads the same family choices instead of repeating independent defaults.
- Keep font conversion, source downloads, and package repairs in personal nixpkgs. The configuration should select packages and policies, without containing a second copy of the build logic.
- Prefer Home Manager's normal profile installation for optional Linux fonts unless the existing XDG placement has a demonstrated requirement. A migration must remove the old managed link and verify selection afterward.

These recommendations reduce separate lists and activation code. They do not imply that identical store paths listed twice consume twice their font-file size.

## Darwin needs a separate installation backend

Home Manager collects font files from `home.packages` and copies them into `~/Library/Fonts/HomeManager`. Its source explicitly records that macOS does not recognize symlinked fonts. [Home Manager Darwin font target](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/fonts.nix).

nix-darwin independently copies `fonts.packages` into `/Library/Fonts/Nix Fonts`. Its activation preserves full store paths in the destination hierarchy so an unchanged size and timestamp cannot conceal changed bytes. It recognizes lowercase `.ttf`, `.ttc`, `.otf`, and `.dfont` suffixes. [nix-darwin font module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/fonts/default.nix).

Recommendation: share the catalog and family preferences across platforms, but keep native installation and renderer tests separate. When the same packages enter both Darwin modules, they produce separate native copies. Choose a single owner for each collection and verify that a migration removes only the redundant managed files. A Linux `fc-match` result cannot establish that a native macOS application uses the intended face.

## Matching rules should preserve document intent

Fontconfig edits patterns in parse order. Included numbered configuration files are sorted, but the effect also depends on the edit operation and binding. Strong family bindings outrank language matching; weak bindings follow it. Aliases can insert preferred, acceptable, or final fallback families. `target="pattern"` changes selection; `target="font"` changes the selected face's rendering. Fontconfig can return a nearest match even when the requested family is absent. [Fontconfig manual](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#fontmatching).

Recommendation: preserve explicitly requested families where possible, use generic-family aliases for defaults, and reserve strong substitutions for documented compatibility requirements. Do not assume that naming a file `99-...` makes all its rules authoritative. Record `fc-conflist` and the resulting pattern when diagnosing precedence.

For language coverage, test Japanese, Korean, simplified Chinese, and traditional Chinese independently. Noto's full CJK fonts support regional forms through language tagging and the OpenType `locl` feature; the selected family's regional suffix alone does not establish which glyphs an application renders. [Noto CJK deployment guidance](https://github.com/notofonts/noto-cjk/blob/main/Sans/README.md#language-specific-otfs). Test shaping before changing fallback order. Keep emoji available through the emoji family and verified fallback rules without putting emoji before normal text families. Bare digits, punctuation, and text-presentation symbols deserve explicit regression coverage.

## Cache and performance policy

Nixpkgs' `makeFontsCache` runs the host Fontconfig executable, through an emulator when necessary, because its caches depend on architecture. It writes cache data into a derivation output. [Cache builder](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/libraries/fontconfig/make-fonts-cache.nix).

NixOS `fonts.fontDir.enable` creates the legacy X11 font directory, including `fonts.dir` and `fonts.scale`. It is separate from modern Fontconfig registration. [X11 font-directory module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/fonts/fontdir.nix).

Recommendation: use those upstream cache builders before adding unconditional login-time cache rebuilding. Measure cold font enumeration, warm enumeration, profile build time, and native-copy size separately. A large installed collection can be acceptable when the user needs it; do not remove language coverage on the assumption that every unused family causes a visible delay. Offer an opt-in design collection if measurements show the broad Google Fonts bundle dominates installation or scanning.

The local optional-emoji module already refreshes its custom directory only when the managed link changes. That is more focused than rebuilding every cache at each login. Moving it into the normal profile is an architectural simplification to evaluate, not an urgent rendering fix.

## Bitmap settings are distinct

The NixOS `allowBitmaps = false` implementation rejects `scalable=false`. Fontconfig describes scalable fonts as fonts with outlines or color; this is not a blanket prohibition of color bitmap emoji. `useEmbeddedBitmaps` separately controls the selected font's embedded-bitmap preference. [NixOS bitmap rules](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/fonts/fontconfig.nix), [Fontconfig properties](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#fontproperties).

Recommendation: improve comments that describe all bitmap settings as a universal rendering-quality improvement. Keep browser downloadable-font sanitizer policy separate. The current decision to leave downloaded color bitmaps disabled should not be reversed merely to make a legacy test page pass.

## Package quality and reproducibility

Nixpkgs provides an `installFonts` hook for common font formats and a separate `webfont` output for WOFF files. A custom installer remains justified when it validates manifests, handles unusual archives, or preserves licenses that a generic copy step would omit. [Font installation hook](https://github.com/NixOS/nixpkgs/blob/master/doc/hooks/installFonts.section.md).

Nix checks the expected content hash of a fixed-output derivation. `preferLocalBuild` influences scheduling; `allowSubstitutes = false` suppresses substitution and can itself be overridden by a Nix setting. Neither attribute prevents someone from uploading an output. [Nix advanced attributes](https://nix.dev/manual/nix/2.32/language/advanced-attributes.html).

Nixpkgs recommends specific license metadata. Its generic `unfree` and `unfreeRedistributable` values have different redistribution meanings. The package's modification steps matter when redistribution is conditional on leaving upstream bytes unchanged. [Nixpkgs license metadata](https://nixos.org/manual/nixpkgs/stable/#sec-meta-license).

Recommended package contract:

- Pin the release or commit, download hash, and conversion dependencies. Record the upstream font version separately from the package revision.
- Retain original notices and state which files or glyphs were modified. Identify third-party conversions as such.
- Verify installed payload hashes, PostScript identities, expected faces, and supported suffixes. Reject ambiguous duplicates instead of silently selecting whichever file is encountered first.
- For generated fonts, use stable ordering and timestamps and compare two clean builds when changing the generator.
- Keep redistribution eligibility in the cache-publishing policy. Build preferences and license metadata are not enforcement against arbitrary uploads.
- Include a compact machine-readable inventory with family names, versions, color tables, source provenance, and intended platforms. Do not label opaque font data as native executable code merely to fill a metadata field.

## Tests should follow the rendering path

The upstream NixOS test checks actual `fc-match` results for the four generic families, rather than merely evaluating option values. [NixOS default-font test](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/fontconfig-default-fonts.nix).

CSS defines family matching and cluster matching separately from font-resource loading. A `local()` lookup and a downloaded `url()` resource therefore exercise different paths. [CSS Fonts Level 4 working draft](https://www.w3.org/TR/css-fonts-4/#font-matching-algorithm). OpenType COLR processing occurs after layout; color-table presence alone cannot establish that a multi-codepoint sequence shapes correctly. [OpenType COLR specification](https://learn.microsoft.com/en-us/typography/opentype/spec/colr).

Recommendation: retain the repository's sequence and browser checks, and add a small declarative selection test that runs with an isolated Fontconfig configuration. Assert the resolved family and file, not merely a successful command. Cover normal and bold/italic text, CJK language selection, bare digits, text versus emoji presentation, ZWJ sequences, skin tones, and explicit alternate emoji families. Keep native Qt/GTK and Darwin checks separate from Zen checks. A screenshot of a site's obsolete downloaded font is not evidence that the installed package regressed.

## Local review targets

The following are source-level observations for the integrated review, not confirmed runtime failures:

- `modules/shared/fonts.nix` uses the same broad package list in NixOS, Darwin, and Home Manager. Its comment prevents duplicate Apple document fonts on Darwin, but the rest of the shared collection still warrants the same ownership check.
- `modules/nixos/locale/fonts.nix` contains another large package list and a second Twemoji policy-removal override. The integrated audit found it inactive for desktop. Treat it as a maintainability issue, not evidence of desktop bitmap settings or a rendering regression.
- `modules/shared/font-selection.conf` is shared between a system rule and a user rule. Keeping one source is useful; document why both installation scopes need the filter.
- `modules/home/desktop/optional-emoji-fonts.nix` uses a separate Linux font directory and activation refresh. Compare it with a normal profile-based installation before preserving that extra mechanism permanently.

The integrated review should prioritize findings from evaluated host configuration and installed font inventories over these source-level candidates.
