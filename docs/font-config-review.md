# Font configuration review

Reviewed 2026-09-06. This document records the pre-change audit. The subsequent
[implementation and validation guide](font-configuration.md) describes the
implemented changes and preserves the user's choice of the full design library.

The configuration has strong coverage and several useful, tested compatibility
repairs. I would improve ownership, package composition, and automated checks
before changing how text looks. The largest concrete opportunities are the
whole Google Fonts collection used to supply one primary family, and duplicate
system/user installation ownership on macOS.

## What a high-quality configuration should provide

| Property | Practical requirement |
| --- | --- |
| Predictable selection | Explicit primary families and tested fallback; requested document fonts remain usable. |
| Coverage | Real shaping and rendering for scripts, combining marks, emoji sequences and presentation selectors. |
| Clear ownership | One installation owner per collection, with separate system, user and native macOS responsibilities. |
| Reproducibility | Pinned source bytes, recorded identity/version, deterministic conversions, retained notices. |
| Maintainable policy | One catalog and role definition; package repairs belong in personal nixpkgs. |
| Measured cost | Know file count, installed size, cache cost and build time before promising a speed improvement. |
| Safe browser behavior | Installed-font support and downloaded-font validation remain separate concerns. |
| Upgrade confidence | Changes run selection, shaping, browser and relevant native-platform checks. |

These criteria follow the upstream installation, matching and cache mechanisms
collected in the [primary-source guidance](font-config-upstream-guidance.md).
They are design recommendations, not a single official universal font preset.

## Current evidence

The live Linux inventory resolves 9,320 visible paths to 5,218 distinct font
files totaling 4.60 GB. Of these, the filtered Google Fonts package contributes
3,845 files and 2.35 GB. These are file sizes, not RAM use, download sizes or the
full build closure. The user's Fontconfig cache occupies about 1.8 GiB across
1,623 entries. I have not established which entries are stale or measured an
application slowdown caused by this collection.

The active primary roles resolve to Inter, Literata, MonaspiceNe Nerd Font and
Noto Color Emoji. Evaluated desktop settings use grayscale antialiasing, slight
hinting, embedded bitmaps enabled and `fontDir.enable = false`. System and user
fallback lists agree. The alternative values in `modules/nixos/locale/fonts.nix`
are not active desktop settings.

The Mac configuration evaluates with 43 distinct package names present in both
its system font list and Home Manager package list, including the primary roles
and most of the broad collection. This is a configuration finding; I did not
inspect or render fonts on a live Mac during this review.

Evidence: [inventory and representative overlaps](assets/font-config-review/inventory.json),
[effective desktop settings](assets/font-config-review/desktop-effective.json),
[Darwin ownership](assets/font-config-review/darwin-ownership.json), and
[loaded Fontconfig files](assets/font-config-review/loaded-config.txt).

## Improvements, in priority order

### 1. Give font collections one installation owner on Darwin

`modules/shared/fonts.nix:126` installs the broad catalog through nix-darwin.
The Home Manager branch at line 141 installs it again through `home.packages`.
The existing exception prevents duplicate Apple document collections but does
not cover the other 43 overlapping package names.

This differs from listing an identical Nix store path twice on Linux. The two
Darwin modules copy fonts into separate native directories. Choose system
ownership for shared fonts, or user ownership for personal collections, and
configure the other scope to select those fonts without copying them again.
Account for Stylix automatically installing its four role packages when
implementing this. [nix-darwin installation](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/fonts/default.nix),
[Home Manager native installation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/fonts.nix).

Success means the evaluated overlap is intentional and minimal, managed native
copies are removed by the appropriate activation module, and Font Book/native
applications still find the required families. Never delete unrelated user or
Apple system fonts to accomplish this.

### 2. Decouple the serif role from the full Google Fonts catalog

`modules/shared/stylix.nix:142` uses the entire filtered Google Fonts package
for Literata. This makes a required desktop role depend on thousands of optional
design fonts, even for a host that only wants the primary typography.

The pinned nixpkgs already provides `pkgs.literata` 3.103. It also supports
`google-fonts.override { fonts = [ ... ]; }` to select families. Use a dedicated
Literata package for the role, and expose the broad design library as a separate
collection. Keep that library available if it is useful to the user.
[Dedicated package](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/li/literata/package.nix),
[Google Fonts selection interface](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/go/google-fonts/package.nix).

Changing only Stylix's provider will not remove the bulk package while the shared
collection still installs it. A selected Google Fonts output also still fetches
its broad upstream source; it mainly narrows installed output. Verify Literata
version, variable axes, weight/style selection and rendering before switching.
Do not claim a startup speedup without measuring it.

### 3. Consolidate the package catalog and eliminate dormant policy copies

There are overlapping catalogs in `modules/shared/fonts.nix` and
`modules/nixos/locale/fonts.nix`, plus role definitions in the shared Stylix
module and `modules/nixos/stylix-components/fonts.nix`. Twemoji's bundled policy
removal is repeated. The old locale module also enables the legacy font directory
and disables bitmap settings, unlike the effective desktop configuration.

Keep one catalog of roles and optional collections. Make NixOS, Home Manager and
Darwin small installation adapters. Move the Twemoji and collection-cleanup
variants into personal nixpkgs so configuration only selects packages. Migrate
any remaining consumers of the old modules before deleting or deprecating them.
The current desktop is not suffering a bitmap-option conflict; the risk is a
future import silently choosing another policy.

Use ordinary module defaults for user choices. Keep any necessary `mkForce`
where an adapter must replace another module's generated list, and explain why.
Do not replace every override mechanically: list merging and Stylix's generated
defaults must be tested together. Fontconfig rule precedence also depends on
binding and edit operations, not just numeric filenames.
[Fontconfig matching rules](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html#fontmatching).

### 4. Make duplicate handling a reviewed policy instead of a growing deletion list

The inventory found 1,211 PostScript identity groups across multiple distinct
files. That count includes valid static/variable and TTF/OTF alternatives; it is
not a count of 1,211 bugs. Concrete examples worth deciding explicitly include
old corefonts Arial/Times New Roman alongside their newer Windows 11 versions,
and Google Fonts Roboto/Inter alongside dedicated packages.

Record each primary family's authoritative provider. Fail checks for a second
unexpected Noto Color Emoji provider, a compatibility-test face becoming visible,
or another known regression. Report other duplicates for review, with version,
container, axes and file hash. Keep intentional alternatives where document
compatibility or design use requires them.

The existing narrow Noto exclusion is justified by observed missing emoji in the
older face. It should remain until obsolete managed profiles have migrated.
Do not generalize it into indiscriminate family-name removal, which can discard
useful styles or variable axes. See the [earlier measured regression](system-font-audit-research.md).

### 5. Turn the accumulated font checks into one repeatable validation entry point

The repository has meaningful browser and shaping checks, but many results are
manual artifacts rather than a test suite wired to package/configuration changes.
`pkgs/flake/dev/emoji-fonts.nix:5` registers three emoji packages, but omits the
new Apple emoji package. Its install checks run when built explicitly; they are
not yet part of that dedicated emoji check set.

Add cheap isolated Fontconfig selection tests for primary family/file identity,
normal/bold/italic variants, expected duplicate exclusions and alternate emoji
families. Run the existing package checks in CI, and expose one documented command
for browser checks using pinned Unicode fixtures and explicit tool dependencies.
NixOS itself uses executable `fc-match` assertions for its default-family test.
[Upstream selection test](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/fontconfig-default-fonts.nix).

The generic checker at `tests/fonts/check_emoji_coverage.py:73` assumes every
supported emoji becomes one glyph. That is suitable for the current Noto contract,
but not universal: Apple correctly uses two positioned bitmap layers for 396
sequences. Unify common fixture/loading/report code while retaining explicit
font-specific shaping contracts. Distinguish coverage, composition, visible
artwork and exact appearance; a width-only test cannot prove all four.

Add a small Qt/GTK rendering sample and native macOS smoke test before claiming
all-platform rendering compatibility. Also exercise bare digits, punctuation,
text/emoji selectors, mixed skin tones and CJK language tags. A legacy website's
rejected download remains a separate web-resource test, not an installed-font
regression. [CSS font matching and resource selection](https://www.w3.org/TR/css-fonts-4/#font-matching-algorithm).

### 6. Simplify optional-font activation when it can be migrated cleanly

`modules/home/desktop/optional-emoji-fonts.nix` uses a custom Linux XDG directory,
a symlink join, and a conditional cache refresh. It works, and refreshing only
on link changes is sensible. However, these packages already install standard
`share/fonts` files and could normally use Home Manager's profile font/cache
mechanism. [Home Manager implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/fontconfig.nix).

Evaluate migrating them into `home.packages`, with removal of the previous managed
link and checks in a fresh application process. Keep the custom mechanism if it
has a documented requirement the normal module cannot meet. Remove temporary
manual activation roots only after a managed generation references the replacement.
Do not add blanket `fc-cache -f` at every login or purge all caches to make an
audit number smaller. Measure relevant cache use first.

### 7. Standardize the personal font-package contract

The Apple manifest installer and source-pinned emoji packages are a good base.
Extend the same provenance/identity approach to the Windows importer: it currently
checks for extracted files and a license, but does not validate a recorded face
inventory. Its output disables substitutes while its source fetch has no matching
unfree/source policy metadata. Review source and output consistently, and use
font-data provenance metadata rather than `binaryNativeCode`.

Give every converter a record of source release, original font version, modified
tables or glyphs, output hash and notices. Keep the Apple emoji Noto supplement
visible in that record. Add an explicit release-update check for Apple emoji;
currently it deliberately removes the inherited Apple-catalog updater and has a
manual update procedure. Verify availability as well as content hashes, because
pinning cannot make a deleted upstream release downloadable forever.

`allowSubstitutes` and `preferLocalBuild` are not upload controls. Keep any cache
publication restriction in the actual publishing policy, especially for proprietary
font data. This is packaging guidance, not a determination of redistribution
rights. [Nix attribute semantics](https://nix.dev/manual/nix/2.32/language/advanced-attributes.html),
[Nixpkgs license metadata](https://nixos.org/manual/nixpkgs/stable/#sec-meta-license).

## Settings I would keep for now

The four primary families, Noto emoji default, optional alternate emoji families,
grayscale antialiasing and slight hinting all have working evidence. I would not
change them as a general cleanup. The existing monitor review supports keeping
rendering settings until an application-specific comparison identifies a problem.
[Monitor review](monitor-fontconfig-research.md).

Keep `gfx.downloadable_fonts.keep_color_bitmaps = false`. The screenshot discussed
earlier exercises a downloaded SBIX file rejected for a missing required table;
installing more fonts does not repair that resource. This is separate from
Fontconfig's `allowBitmaps` and `useEmbeddedBitmaps` switches.
[Observed web-font failure](mutant-standard-emoji.md).

Keep the Gecko generic substitution limit of 127 pending a measured replacement.
It fixed missing script coverage with the current stack. A smaller font collection
may allow a shorter search list, but selecting 3, 8 or 16 just because it looks
simpler would risk restoring the earlier failure. Compare coverage and application
cost together. [Mozilla's coverage discussion](https://bugzilla.mozilla.org/show_bug.cgi?id=1970417),
[local before/after evidence](system-font-audit-research.md).

Do not change CJK ordering on `fc-match` family names alone. The audit did select
SC first for a Japanese query, but HarfBuzz produced the same Japanese glyphs
from SC, JP and TC faces when supplied `language=ja`; Traditional Chinese likewise
selected its regional forms. The tested text was 骨直令漢. That behavior is supported
by Noto's language-tagged `locl` feature. Add this regression and test applications
that omit language tags before changing policy.
[CJK shaping evidence](assets/font-config-review/cjk-shaping.json),
[Noto's regional-font guidance](https://github.com/notofonts/noto-cjk/blob/main/Sans/README.md#language-specific-otfs).

## Suggested implementation sequence

1. Add selection, ownership and duplicate-provider checks around today's working defaults.
2. Give Literata a dedicated provider and define required versus optional collections.
3. Correct Darwin ownership, including Stylix's automatic package installation.
4. Migrate old catalogs and package overrides into the shared catalog/personal packages.
5. Integrate emoji/browser checks, then assess optional-font activation and cache cost.

This sequence keeps behavior testable while module boundaries change. Broad
collection pruning should follow the user's font needs and measured costs.

## Scope and limits

I read the shared/system/user font modules, Stylix roles, browser and terminal
integration, personal Apple/Windows/emoji packages, prior rendering evidence and
upstream implementations. I inventoried all files visible through the active Linux
Fontconfig configuration and evaluated desktop and Mac configuration. This is not
an exhaustive glyph-level or security audit of every font file. Mac native
rendering and application startup benchmarks remain unmeasured.
