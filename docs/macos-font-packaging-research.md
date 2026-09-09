# Packaging macOS fonts with Nix

Research date: 2026-09-06. This note distinguishes a reproducible package, a source URL that remains downloadable, and permission to use or redistribute the resulting fonts. The findings concern Apple-distributed fonts. A third-party font installed on a Mac still needs its own upstream source and license.

## Answer

Many macOS fonts can use ordinary Nix fixed-output downloads and standard font installation directories. Apple's downloadable font assets are especially promising: their catalogs expose individual ZIP URLs, build identifiers, and integrity metadata. A full macOS installer is unnecessary for those assets.

There is no verified universal source containing every macOS font with a permanently available versioned URL. The SF developer downloads use mutable URLs. The asset catalogs cover a different, large collection and omit several core fonts. Full installer extraction or a recorded local import remains a candidate for the missing system files, but this research did not validate extraction of a complete current macOS system-font set. Licensing and rendering also prevent an unconditional claim that every Apple font can become an ordinary redistributable Linux font package.

## Source classes

| Font source | Version pinning available | Packaging approach | Limit |
| --- | --- | --- | --- |
| SF Pro, Compact, Mono, New York and SF script extensions | Hash the current DMG and record its embedded version | Extract the DMG and installer payload | Public download URLs have no version component or verified historical archive |
| Apple's Font Book and document-support assets | Concrete CDN ZIP URL, asset build, hash | Generate a manifest during updates, fetch ZIPs independently | Catalogs change; platform delivery and duplicate versions need selection |
| Core fonts bundled with macOS | Pin an OS installer or an imported archive and its build | Extract an identified OS payload or import files from a matching Mac | Complete extraction and coverage remain unverified here |
| Third-party fonts present on a Mac | Depends on the vendor | Prefer the original vendor or open-source release | A macOS installation does not create new redistribution rights |
| Legacy suitcase and resource-fork fonts | Pin the original archive | Preserve all font data, evaluate any permitted conversion separately | Ordinary copying and modern renderer support are insufficient guarantees |

Apple distinguishes installed or downloadable fonts from document-support fonts. The latter can be available only to documents already using the font or apps requesting it by name. Apple also says macOS updates can introduce font updates, so an OS marketing version alone is not a complete content pin. [Apple's Tahoe font inventory](https://support.apple.com/en-ie/122869).

## Developer font downloads

Apple's current font page links to eight DMGs beneath `https://devimages-cdn.apple.com/design/resources/download/`: `SF-Pro.dmg`, `SF-Compact.dmg`, `SF-Mono.dmg`, `NY.dmg`, `SF-Arabic.dmg`, `SF-Armenian.dmg`, `SF-Georgian.dmg`, and `SF-Hebrew.dmg`. These are direct downloads without version components. HTTP HEAD requests returned 200 with those same final URLs. No supported immutable historical URL scheme was established. [Apple's font downloads](https://developer.apple.com/fonts/).

The observed SF Pro and Compact responses had an August 5, 2026 modification date; the other six had July 10, 2025 dates. These HTTP dates identify an observation, not the font's version. Pinning a hash prevents silently receiving changed bytes, but a later replacement at the same URL can make an older package impossible to fetch anew.

A small end-to-end extraction check used the current [SF Mono DMG](https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg). The file was 1,605,572 bytes with SHA256 `6d4a0b78e3aacd06f913f642cead1c7db4af34ed48856d7171a2e0b55d9a7945`. On Linux, 7-Zip 26.02 extracted the DMG's HFS content, the XAR installer package, the gzip payload, then its cpio archive. The payload contained 12 OTF files. `PackageInfo` identifies `com.apple.pkg.SFMonoFonts` version `6.0.1.1726709071`. Fontconfig read an extracted face as SF Mono Medium Italic. This establishes extraction and font parsing for this release, not full application rendering or all eight DMG variants.

A package can therefore expose an honest version today. Its remaining source problem is historical availability. Adding a Nix `version` attribute or changing a download filename does not turn the upstream URL into a versioned endpoint.

The existing [Lyndeno/apple-fonts.nix inputs](https://github.com/Lyndeno/apple-fonts.nix/blob/master/flake.nix) use these same mutable downloads. Its [package implementation](https://github.com/Lyndeno/apple-fonts.nix/blob/master/fontPackage.nix) demonstrates DMG/payload extraction into standard font directories, but only collects TTF and OTF files and does not declare font license metadata or a package version. It is useful extraction precedent, not a solution to complete coverage or historical source availability.

## Apple's downloadable asset catalogs

Directly fetched and parsed Apple's [Font7 catalog](https://mesu.apple.com/assets/macos/com_apple_MobileAsset_Font7/com_apple_MobileAsset_Font7.xml) and [Font8 catalog](https://mesu.apple.com/assets/macos/com_apple_MobileAsset_Font8/com_apple_MobileAsset_Font8.xml) using Python `urllib.request` and `plistlib`. These are observations of Apple's actual service, not a claim that Apple documents a permanent public API contract.

| Observation | Font7 | Font8 |
| --- | --- | --- |
| Asset records | 535 | 363 |
| Font descriptors in `FontInfo4` | 1,844 | 1,303 |
| Distinct family-name strings | 613 | 610 |
| Sum of advertised download sizes | 1,190,549,712 bytes | 1,058,363,299 bytes |
| Catalog SHA256 | `554f46bbb3ad61beb24e6a831ba875e635910e3abcb42076a8b5bcb69543b697` | `bf378d700cd88b67327a595a51fc9900090c3952a144a80b38b322dd01c3fee9` |

An asset provides `Build`, `_MasteredVersion`, font family/style/PostScript names, `_DownloadSize`, `_MeasurementAlgorithm`, `_Measurement`, `__BaseURL`, and `__RelativePath`. The two URL fields concatenate to a concrete Apple CDN ZIP address. Catalog measurements in the tested records use SHA-1. A Nix package should also compute and pin its own SHA256 over the downloaded ZIP.

Two small downloads verified that this mechanism works:

| Sample | Asset build | ZIP bytes | ZIP SHA256 | Font payload |
| --- | --- | --- | --- | --- |
| [Font7 Al Bayan](https://updates.cdn-apple.com/2022/mobileassets/012-38072/C729B731-C859-46EA-855B-69F685A1339D/com_apple_MobileAsset_Font7/701405507c8753373648c7a6541608e32ed089ec.zip) | `10M1360` | 100,063 | `916ad7c748f058d62264efe63160e6783ca915092cd301efba3e6184e210b2fe` | `AssetData/AlBayan.ttc` |
| [Font8 Hopper Script](https://updates.cdn-apple.com/2025/mobileassets/072-04650/9FABB3FE-D4A6-4563-8CCE-20B5E692A0C9/com_apple_MobileAsset_Font8/00320fe025e4e2ee4cd6bceca5d4cebc94a8dcd9.zip) | `10M11177` | 108,068 | `4774fbfe669176575983ab2b6cda044bcb8e0bdd4b6685c61c6d24ea9917bb53` | `AssetData/HopperScript.ttf` |

Both ZIPs matched their advertised size and SHA-1 measurement. Python's standard ZIP reader extracted each font without installing it. `fc-scan` recognized all four Al Bayan collection faces, including two internal PUA faces, and Hopper Script Regular. No catalog signature validation or rendering test was performed.

These addresses contain release-specific identifiers and worked at the recorded versions. The observation does not prove permanent retention. Hash pinning makes a changed response fail; it cannot restore a deleted upstream file.

Font8 descriptors contain `PlatformDelivery` values such as `macOS`, `macOS-download`, `macOS-autoactivated`, `macOS-invisible`, and `catalog`. A raw union of every record would discard Apple's activation policy and include entries intended for other platforms. Font7 also contains duplicate family versions, for example two Monaco assets with different builds. Select the intended OS generation and faces explicitly. Asset build identifiers are not font version strings or macOS release numbers.

There is no single asset build for an entire catalog snapshot. Font7 contains six different `Build` values. Font8 contains 359 records at `10M11177` and four at `10M13685`. Record a collection snapshot separately from each asset's build.

Neither observed catalog contained family names exactly matching Apple Color Emoji, SF Pro, Menlo, Times New Roman, or Helvetica. Both contained Helvetica CY and PingFang. This is enough to reject the claim that either catalog alone covers all system fonts. It does not prove those missing names are absent from every Apple source or every hidden/internal family.

The proposed Nix workflow is an updater that reads the catalog, selects assets, downloads them, inspects their files and licenses, and writes a reviewed manifest of concrete URL, SHA256, build, font versions, PostScript names, and expected payload paths. Normal evaluation and builds use that manifest. They should not discover the latest fonts from the live catalog. This is a design recommendation derived from the service inspection.

## Core system fonts and complete collections

Apple supports requesting an available full installer by macOS version with `softwareupdate --fetch-full-installer --full-installer-version <version>` and listing currently available installers. Availability depends on the Mac and the versions still offered. This is a supported version-selection mechanism, not a promise that all past versions remain downloadable. [Apple's installer download instructions](https://support.apple.com/en-gb/102662).

The upstream [Munki installer scripts](https://github.com/munki/macadmin-scripts) show that Apple's software-update catalogs can supply packages used to assemble macOS installers. They also document that their scripts run on macOS and invoke Apple's installer. They do not establish that a current complete macOS filesystem can be extracted on Linux by applying the Windows ISO recipe unchanged.

For missing built-in fonts, a pinned installer payload is a reasonable investigation target. A deterministic archive exported from a known Mac build is another source option. Record file hashes and internal font versions, and import the archive as an explicit fixed input. Reading `/System/Library/Fonts` directly during a derivation would make the build depend on the host OS. An installed system also need not contain every on-demand asset, so a local export cannot claim completeness without an inventory.

## Formats and native behavior

Current Apple documentation lists TrueType, variable TrueType, TrueType/OpenType collections, OpenType, and OpenType-SVG as supported. It says legacy suitcase TrueType and PostScript Type 1 LWFN fonts may work but are not recommended. Therefore even native macOS does not offer a blanket promise for every historical font format. [Font Book format support](https://support.apple.com/guide/font-book/install-and-validate-fonts-fntbk1000/11.0/mac/26).

FreeType documents support for TTF/TTC, OpenType/CFF/collections, Type 1, and several bitmap formats. HarfBuzz automatically processes AAT shaping tables on every platform, so AAT does not by itself require converting Apple fonts. Neither fact establishes pixel-identical Core Text output or support for every application-specific font feature. [FreeType format support](https://freetype.org/freetype2/docs/index.html), [HarfBuzz AAT support](https://harfbuzz.github.io/integration-coretext.html).

Preserve original files and collection faces where possible. Identify fonts by their data and PostScript names rather than filename extension alone. Validate collection contents, variable axes, color tables, and representative shaping/rendering separately. Legacy resource-fork fonts need an archive that actually retains the resource data; an empty data fork copied into the Nix store is not a usable font. Conversion can alter behavior and must also be permitted by the font license.

FreeType also has non-Mac loaders for dfont, MacBinary, and resource font data. A dfont is therefore not automatically unusable on Linux. Apple Color Emoji needs its own assessment: FreeType's `sbix` support accepts PNG glyph images, but excludes JPEG, TIFF, and Apple-specific formats outside the OpenType specification. Inspect the selected release's actual tables and test its renderer before promising compatibility. [FreeType Mac font loaders](https://github.com/freetype/freetype/blob/master/src/base/ftobjs.c), [FreeType sbix support](https://freetype.org/freetype2/docs/reference/ft2-font_testing_macros.html#ft_has_sbix).

## Licensing affects the package design

The current macOS Tahoe license, section 2E, grants use of bundled fonts to display and print while running the Apple software, with embedding subject to each font's restrictions. This does not establish permission to extract the entire collection for general Linux use or to redistribute it in a public binary cache. Separately licensed third-party fonts require their own assessment. [macOS Tahoe license](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf).

The SF Mono DMG's embedded `Resources/English.lproj/License.rtf`, agreement EA1758 dated May 20, 2021, restricts use to Apple-platform UI mock-ups, imposes developer eligibility and use conditions, and prohibits unauthorized redistribution and modifications. The older SF and Compact agreements displayed on Apple's website also restrict their use. An implementation must retain and review the actual agreement bundled with each selected release; one generic license label does not summarize every Apple font. [Inspected SF Mono distribution](https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg), [Apple's published font agreements](https://developer.apple.com/fonts/).

These are concrete packaging limits, not a conclusion that downloading every font is prohibited. The available terms do not support advertising a universal, freely redistributable Apple-font collection. Marking a derivation unfree, disabling substitutes, or importing a local archive changes Nix's behavior; none grants additional font-use rights.

## Comparison with this repository

The relevant local package is `ttf-ms-win11-auto`. Its [source manifest](../pkgs/pkgs/by-name/tt/ttf-ms-win11-auto/source.nix) pins Windows build `10.0.26200.6584`, a concrete Microsoft Enterprise Evaluation ISO URL containing that build, and a SHA256 hash. Its [updater](../pkgs/pkgs/by-name/tt/ttf-ms-win11-auto/update.py) discovers the current release and resolves the `aka.ms` alias during updates. Normal package builds use the saved URL directly.

The [derivation](../pkgs/pkgs/by-name/tt/ttf-ms-win11-auto/package.nix) uses 7-Zip to extract `sources/install.wim`, then `Windows/Fonts/*` and the license. It installs TTF/TTC files under `share/fonts/truetype`, sets `meta.license = lib.licenses.unfree`, prefers local builds, and disables substitutes for the resulting font derivation. This is an inspection of the current code, not a fresh Windows build or a license audit of that package.

Reuse its separation between source discovery and pinned builds. For Apple catalog fonts, replace the multi-gigabyte ISO with individual ZIP assets. For developer fonts, replace it with a DMG, while accepting the weaker historical availability. Only the missing OS-bundled set calls for investigating a full-installer extraction approach comparable to the Windows package.

The shared [font configuration](../modules/shared/fonts/default.nix) installs the Windows package on both Linux and Darwin. The old [NixOS font module](../modules/nixos/locale/fonts.nix) has a commented `apple-fonts` entry, but this research found no corresponding local Apple package implementation. The shared configuration also installs nixpkgs `corefonts`; that is a separate legacy Microsoft distribution, marked `unfreeRedistributable`, rather than the modern Windows ISO package. [Pinned corefonts package](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/co/corefonts/package.nix).

## Nixpkgs integration and recommendation

Nixpkgs can package a fixed-hash download from an unversioned URL. A version in the URL is not a prerequisite, but a fetchable immutable release improves rebuild availability. When automatic downloads are unavailable, `requireFile` can require an explicitly named, hashed archive supplied by the user. The Nix expression can be shared independently of the proprietary font bytes. Public nixpkgs acceptance remains a maintainer decision, and unfree metadata does not authorize public font caches. [Nixpkgs fetcher documentation](https://nixos.org/manual/nixpkgs/unstable/#requirefile), [Nixpkgs license metadata](https://nixos.org/manual/nixpkgs/unstable/#sec-meta-license).

Use separate packages for developer families, selected catalog assets, and any validated OS-only import. A collection package can compose them later. Prefer `stdenvNoCC`, fixed source hashes, extraction tools in `nativeBuildInputs`, retained license files, and unchanged font bytes. Check expected paths, face identities, and duplicate PostScript names during builds. Keep fallback policy outside the font packages, as the repository already does for optional emoji fonts.

The pinned nixpkgs `installFonts` hook covers TTF, TTC, OTF, OTC and several legacy formats, but omits dfont. Add an explicit installation step for dfont where needed. The pinned nix-darwin activation module only selects lowercase `.ttf`, `.ttc`, `.otf`, and `.dfont`; it omits `.otc` and arbitrary suitcase filenames. That extension filter needs deliberate handling before claiming native installation of every format. Home Manager copies the entire managed `share/fonts` tree. Both native paths copy font contents rather than depending on macOS recognizing Nix-store symlinks. [Pinned installFonts hook](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/in/installFonts/install-fonts.sh), [Pinned nix-darwin font module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/fonts/default.nix), [Pinned Home Manager font module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/fonts.nix).

Start a future implementation with one catalog-backed family and an explicit version manifest. It is the best match for the requested versioned-link behavior and has already passed download, extraction, and font parsing checks. A complete collection would then need a target macOS build, an inventory of its built-in and on-demand faces, a source for every missing file, and validation of the intended uses and renderers.

## What this research verified

Read Apple's current font inventory, format guide, developer downloads and licensing documents. Checked all eight developer download URLs. Parsed two live font catalogs and downloaded two representative ZIP assets. Extracted the current SF Mono payload using Linux tools and inspected its embedded version/license. Parsed the three sample font payloads with Fontconfig.

No fonts were installed or activated. No package code was changed. The research did not download a full macOS installer, build a new Nix derivation, verify every catalog asset, establish universal historical URL retention, or compare rendering on a Mac. Those boundaries are why the recommended architecture separates developer fonts, catalog assets, and OS-only fonts.

## Implementation on 2026-09-06

The personal package repository now provides `apple-fonts`, an opt-in Font8
collection of 323 assets containing 323 font files and 1,186 named faces or
instances. Its selection excludes assets available only to other platforms or
marked only as invisible/catalog entries, and resolves four superseded assets.
There are no duplicate PostScript names in the selected catalog payloads.

Eight separate developer packages contain another 155 font files and 288 named
faces or instances. They remain outside the catalog aggregate. The package
exports individual catalog derivations through `apple-fonts.assets` and a
`fromArchive` function for an explicit hashed archive exported from a known Mac.
The exporter handles regular-file fonts, not every historical resource-fork
format or every on-demand font automatically.

The updater records exact archive hashes, versions, payload paths, file hashes,
and named faces in `sources.json`. It validates Apple asset size/SHA-1 metadata,
computes independent SHA256 pins, and inspects all selected archives before
writing. It retains old sources by content hash in its local cache, including
older developer DMGs after an update replaces the URL lookup entry. Builds
verify the source archive and complete font inventory and preserve font bytes.
They install dfont explicitly and rename `.otc` to `.ttc` to satisfy the pinned
nix-darwin extension filter without converting the font.

All 323 catalog packages, their aggregate, and all eight developer packages
built on Linux with the configuration's pinned nixpkgs. A real SF Mono export
also built through `fromArchive`, retaining its original license. Tooling tests
cover selection conflicts, platform filtering, deterministic export/import,
archive traversal and link rejection, altered/extra fonts, collection extension
normalization, and retention of old mutable downloads. Ruff and type checks
passed. The updater's `--check` reports no pending source changes. Package-repo
flake evaluation passed for all supported systems, and the Darwin collection
derivation evaluates through the main configuration.

No font package was added to active system or Home Manager font selections, and
no system activation ran. Darwin builds and native rendering remain untested.
The implementation does not claim a complete OS-only collection or broader use
rights than the applicable font licenses. Usage and update/import commands are
in the [package guide](../pkgs/pkgs/by-name/ap/apple-fonts/README.md).

## Enabled configuration selection

The follow-up configuration enables 16 catalog assets on the desktop and
MacBook, providing 110 named faces across 15 families:

- Brill
- Canela, Canela Deck, and Canela Text
- Domaine Display
- Founders Grotesk, Founders Grotesk Condensed, and Founders Grotesk Text
- Graphik and Graphik Compact
- Product and Proxima Nova
- Publico Headline and Publico Text
- Spot Mono

These are document and design choices. Every selected asset is advertised as
`macOS-download`, and none of its recorded PostScript names overlapped the
Linux desktop's installed fonts during this check. The selection avoids a
blanket installation of core macOS, Microsoft, or Google duplicates. The SF
and New York developer packages remain available separately for their specified
uses and are not enabled for ordinary desktop typography.

The shared `appleDocumentFonts` list lives in
`modules/shared/fonts/packages.nix`. The desktop's local system-font module
installs it, while the shared Darwin font module installs the same list on the
MacBook. Home Manager does not install these assets a second time. This follows
the hosts' existing module structure without importing the entire shared font
collection into the desktop system profile.

Validation confirmed 16 selected system packages and zero selected Home Manager
packages on each host. Their combined font directory builds successfully. All
15 families match by name in an isolated Fontconfig configuration, while the
four default matches remain Inter, Literata, MonaspiceNe Nerd Font, and Noto
Color Emoji. Both complete system derivations evaluate successfully. No system
activation ran; the additions take effect on the next configuration switch.
Native Mac duplicate resolution and rendering still require an on-device check.
