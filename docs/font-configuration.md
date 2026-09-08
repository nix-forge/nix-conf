# Font configuration and validation

Implemented from the [font review](font-config-review.md). Both personal homes
explicitly select the **full design library**, as requested. Required fonts do
not depend on that collection.

## Ownership and selection

`modules/shared/font-packages.nix` owns the catalog, primary roles, fallback
families and collection selection. `modules/shared/fonts.nix` adapts that catalog
to NixOS, nix-darwin and Home Manager. The old NixOS entry points delegate to the
same definitions. Package modifications live in nixpkgs-personal.

| Role | Provider | Family |
| --- | --- | --- |
| Interface | nixpkgs Inter | Inter |
| Serif | nixpkgs Literata | Literata |
| Monospace | nixpkgs Monaspace Nerd Fonts | MonaspiceNe Nerd Font |
| Default emoji | nixpkgs Noto Color Emoji | Noto Color Emoji |

The Google design variant retains the full upstream collection except duplicate
Inter, Literata and Noto emoji providers and the emoji compatibility test face.
The dedicated packages supply those real families. The variant records every
excluded file and retains upstream license notices. Static and variable styles
elsewhere remain available; a shared PostScript name alone does not justify
deleting a useful alternative. The existing corefonts/Windows and Roboto
overlaps remain intentional; the inventory exposes their versions and hashes
for review instead of changing document metrics globally.

M+ uses the upstream standalone package with smaller collections and a compatible
variant with the full Google collection, avoiding filename collisions. VS Code
keeps its Iosevka Charon Mono terminal fallback even if the design library is off.
Twemoji remains explicitly selectable without its upstream rules overriding
ordinary text and the default emoji family.

On the desktop, Home Manager owns the general collection. NixOS installs the
primary Stylix roles and selected Apple document fonts. Repeated references to
the same immutable Nix package do not create a second physical font provider.
On the Mac, Home Manager owns the general collection in the native user font
directory. nix-darwin owns only the shared Apple document collection; its Stylix
font-package installation is disabled. The ownership check rejects an identical
package in both Mac installation lists.

`typography.designLibrary` supports `full`, `curated` and `none`. The default for
other homes is `curated`; the desktop and Mac explicitly choose `full`.
`typography.optionalEmoji.enable` adds Firefox Emoji, legacy EmojiOne and Mutant,
plus the Apple conversion on Linux. macOS retains its native Apple Color Emoji.

## Import and update contracts

Apple font imports retain their existing pinned manifests and identity checks.
The Apple emoji updater discovers a release, records its versioned asset URL and
commit, verifies the published SHA-256 and PostScript identity, then replaces the
source manifest atomically. `--check` probes source availability even when the
release has not changed. Builds never use the discovery endpoint.

The Windows importer records all 143 payload files, their SHA-256 hashes and all
named faces. It validates extracted and installed inventories, retains the
Windows license, and extracts into temporary build storage. The updater verifies
the next ISO and generates its inventory before writing either pin. A mismatched
source version or changed payload fails the build. Its manifest is excluded from
spellchecking because names such as `constant.ttf` are exact upstream filenames.

Apple and Windows payloads remain unfree. Source and output substitution are
disabled, but those Nix settings do not prevent uploading store paths. The CI
workflow has no font-cache upload step. See each personal package's README for
provenance and update commands.

## Validation commands

Run the collection check without changing the active installation:

```sh
just fonts-check /tmp/font-check
```

Include the installed browser to test actual Zen rendering:

```sh
just fonts-check /tmp/font-check /etc/profiles/per-user/user/bin/zen-beta
```

The equivalent flake app is `nix run .#font-check -- OUTPUT [BROWSER]`. Browser
collection isolation is Linux-only; macOS uses the native check below. The app uses the
same full catalog as the homes, temporary Fontconfig configuration/data/cache
directories, and a fresh browser profile. It scans only `share/fonts`, keeping
license directories out of the font scan. It checks all primary styles, explicit
CJK language shaping, authoritative providers, the default and Apple Unicode 17
emoji coverage, and optional browser suites. It reports duplicate identities
with hashes instead of silently removing them. No user cache is cleared.

CI builds `font-selection` and `font-ownership` on all three supported systems.
The selection check covers 13 role/style combinations, four language tags, and
all 3,953 Unicode 17 emoji entries. Linux CI also renders multilingual samples
through Qt and Pango and runs the digit and multilingual browser checks against
pinned Firefox. Native checks include bitmap scaling rules so color emoji uses
the requested text size. Example outputs: [Qt](assets/font-implementation/qt.png)
and [Pango](assets/font-implementation/pango.png).

The personal repository's CI runs 21 Apple/Windows import and updater tests.
Affected emoji package builds run their full coverage and artwork checks. The
interactive collection command additionally tests all 7,829 Mutant source
encodings and all 3,953 Apple entries in the chosen browser.

The macOS CI step registers the tested primary files only for its own process,
then checks Core Text family selection and multilingual/emoji shaping. On the
configured Mac, test the activated native installation directly with:

```sh
xcrun swift tests/fonts/check_coretext.swift
```

## Activation and cost

The optional emoji module now uses ordinary `home.packages`. Home Manager's
normal font installation and cache lifecycle replaces the old custom XDG
symlink join and cache hook. A normal activation removes its previously managed
`fonts/optional-emoji` and documentation links. Existing running applications may
need to restart to rebuild their internal font lists.

A historical manual Apple test also left a GC root under
`~/.local/state/optional-emoji`. Remove that root only after a managed generation
containing the fonts is active. Do not remove the currently referenced store
paths or run an indiscriminate cache purge. Darwin removes its obsolete system
copies during the normal nix-darwin font activation and Home Manager installs
the user-owned copies.

The review's live baseline is 5,218 distinct files totaling 4.60 GB, with roughly
1.8 GiB of accumulated user Fontconfig caches. The full collection intentionally
remains large. The validation report records candidate file sizes and duplicate
providers, but those figures are not startup time or memory consumption.
Application startup speed and native Mac rendering must be measured on their
respective hosts; no performance improvement is claimed from package count alone.

Grayscale antialiasing, slight hinting, current CJK ordering, the Gecko generic
substitution limit of 127 and disabled downloaded color bitmaps remain the
selected policy. A failed SBIX/CBDT download test does not establish that an
installed emoji family is broken.

## Recorded desktop results

The [candidate collection](assets/font-implementation/selection.json) passed all
13 role/style selections and all four CJK language comparisons. Its general user
font collection contains 5,199 distinct resolved file paths totaling 4.56 GB.
The isolated Fontconfig cache occupied 23.2 MB. This excludes the system Apple
document fonts, and a fresh cache is not directly comparable to the review's
accumulated 1.8 GiB cache. No application startup improvement is inferred.

Zen passed [160 digit samples](assets/font-implementation/digits.json),
[7,829 Mutant encodings](assets/font-implementation/mutant.json), and
[3,953 Apple emoji entries](assets/font-implementation/apple.json), including
3,736 entries with detectable colored pixels. Downloaded color bitmaps remained
disabled. The Noto and Apple shaping checks each passed all 3,953 Unicode entries.
The [multilingual check](assets/font-implementation/multilingual.json) passed
all three scripts; its [negative control](assets/font-implementation/negative-control.json)
rejected all three at a fallback limit of 3. References are discovered from
Fontconfig character coverage rather than assuming one optional family exists.

These tests reused the immutable Home Manager profile from the successful
pre-crash desktop build. Subsequent formatting and typing edits changed some
package derivation paths without changing the font algorithms. A later full
system build stopped at a separate Hyprshell `serde_json` compilation error.
The host has not been activated as part of this implementation. The Mac hostname
was unavailable, so its native Core Text check is implemented in CI but has not
been run against the personal Mac here.

The final scoped Nix build passed `font-selection`, `font-ownership`,
`font-native` and `font-browser`, using the shared build lock with one job and
two cores. The Apple/Windows tooling check passed 21 tests. The repository Python
check also passed on its tested snapshot; subsequent browser-test edits passed
Ruff and their positive/negative rendering checks. Exact Apple family spelling,
including Produkt, is protected from automatic spelling correction.
