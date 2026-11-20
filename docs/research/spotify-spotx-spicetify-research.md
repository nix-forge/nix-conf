# Spotify SpotX and Spicetify integration research

Reviewed: 2026-11-17; primary sources retrieved 2026-11-16–17. Scope: the shared Nixpkgs revision
`b3cff76391a4867236cc135b69a928d873b9f6d0`, local `spotify-spotx`,
SpotX-Nix `9902095a78f97520940cdf8eeb4093d6962dee9f`, and
spicetify-nix `13e6fed4eb99f809d390fb50f591bed6cb716dc0`.
This review supersedes the earlier conclusion that SpotX-Nix supports Linux only.

## Answer

Retain the local package for now. Official SpotX-Nix is a maintained alternative
for both selected platforms and correctly puts Darwin signing after its patch
phase. It is not yet an equivalent replacement for this configuration's client
version, build restrictions, and signing policy. A direct swap would select the
shared Nixpkgs Darwin client `1.2.98.301` instead of the local `1.3.8.620`.
The local variant should enforce noninteractive operation even when a caller
replaces its optional arguments and reject the ineffective `--oldui` option.
Retain the existing UI choices while making those narrow repairs.
[Official recipe](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/nix/package.nix)
[Selected Nixpkgs Darwin source](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/sp/spotify/darwin.nix)
[Local package](../../pkgs/pkgs/by-name/sp/spotify-spotx/package.nix)

The reusable recipe remains in `nixpkgs-personal`; its selection, Spicetify
extensions, theme, managed preferences and application registration remain in
the root configuration. Native macOS acceptance remains necessary before changing
the client archive, signing method, or packaging owner.

## Findings and sources

### Official recipe parity

The inspected source includes the complete recipe, flake outputs and lock file,
non-flake entry point, compatibility and Darwin-verification scripts, and both
workflows. The flake exports `x86_64-linux` and `aarch64-darwin`; it does not export
ARM Linux or Intel Darwin packages. The source supports the README's platform
claim. It overrides incoming `spotify`, reads SpotX's supported version from the
pinned script, rejects newer clients, runs SpotX in `postInstall`, deletes backup
files, and signs Darwin in `postFixup`.
[Flake](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/flake.nix)
[Recipe](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/nix/package.nix)

| Property | Official SpotX-Nix | Local package |
| --- | --- | --- |
| Spotify source | Incoming Nixpkgs package on both platforms | Incoming Nixpkgs on Linux; pinned vendor update archive on Darwin |
| Selected client | Shared input: Linux `1.2.95.453.g0eeebbed`, Darwin `1.2.98.301` | Same Linux client; Darwin `1.3.8.620` |
| Patch arguments | Arbitrary shell-escaped list, empty by default; README warns against installer and interactive options | Evaluation-time allowlist; adapter owns output path, forced version and Darwin signing/update controls |
| Offline restrictions | `SPOTX_BUILD_MODE=true` and temporary `HOME`; no explicit network-command blocker | Same controls plus failing `curl` shim; sandboxed output mutation |
| Patch completion | Relies on script exit | Also requires SpotX marker in patched `xpui.spa` |
| Darwin adaptation | Replaces `/usr/bin/xattr` with `true` | Also adapts `file`/`tr` and architecture-description matching |
| Darwin signing | `rcodesign sign` in `postFixup` | Explicit phase after `postInstall`, hardened-runtime flag, declared entitlements and outer seal existence check |
| Apple verification | Native workflow runs recursive strict `codesign` verification | Historical native verification; current revision still needs a native check when changed |

The selected versions are source observations, not claims about Spotify's latest
release. See the shared Nixpkgs [Linux recipe](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/sp/spotify/linux.nix)
and [Darwin recipe](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/sp/spotify/darwin.nix),
and the local [source metadata](../../pkgs/pkgs/by-name/sp/spotify-spotx/source.nix)
and [build scripts](../../pkgs/pkgs/by-name/sp/spotify-spotx/scripts/).

The official native checker establishes an ARM64 executable, absence of backup
files and Mach-O Nix store references, and a valid complete signature. It does
not inspect SpotX's marker or a Spicetify theme, extensions, account login,
playback, permission continuity, or launch behavior. Its update workflow gates
lock updates on native builds and that signature check. Those are useful upstream
checks, but they do not establish local composition parity.
[Darwin checker](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/scripts/check-darwin-app.sh)
[Update workflow](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/.github/workflows/update.yml)

### Source pins and update readiness

These unpacked SHA-256 hashes were independently obtained with
`nix store prefetch-file --unpack --json` against immutable GitHub archives:

| Source | Revision | Unpacked hash |
| --- | --- | --- |
| SpotX-Nix | `9902095a78f97520940cdf8eeb4093d6962dee9f` | `sha256-AE6e2riL8WpTpdKjcMMrcBOlqOluy6I2xEvp7YQxEQU=` |
| Its SpotX-Bash input | `48bd283fa7877a280bf1a02db6ef2110f3e3e268` | `sha256-mbuJpNtMxsYOYJUeH6q9/Oe1b2jlRfi+OeE5o6oV7Ys=` |

The second hash matches the official lock file. That lock selects Nixpkgs
`d5cc6833999746cffdfe0598f7bc801a57b887a9`; using the overlay with this
configuration's shared Nixpkgs input selects this configuration's Spotify instead.
Do not silently substitute a second package set or update the shared input to
make a migration appear compatible.
[Official lock](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/flake.lock)

Local metadata pins SpotX-Bash `db0583a456fab7b0488c92fd471e6a260e08b995`
and the Darwin `1.3.8.620` archive. New upstream SpotX-Bash supports
`1.3.9.2055.g806b5b278de8`, but updating the patcher and vendor archive still
requires their atomic source refresh and native composition review. The existing
archive authorization expires on 2026-12-06 at 16:28:08 UTC; the updater requires
at least seven days remaining. No new Spotify binary was fetched or accepted by
this source review. A hash proves content identity, not permission or runtime
compatibility.
[New SpotX script](https://github.com/SpotX-Official/SpotX-Bash/blob/48bd283fa7877a280bf1a02db6ef2110f3e3e268/spotx.sh)
[Local updater](../../pkgs/pkgs/by-name/sp/spotify-spotx/update.py)

### Immutable build and ordering

Keep the order Spotify, SpotX, Spicetify, final Darwin signing. The selected
Spicetify builder appends `backup apply` to the base package's `postInstall`.
Official SpotX-Nix's later `postFixup` is compatible with that ordering when the
base package executes its ordinary fixup phase. An explicit local signing phase
is also valid. Missing named signing hooks are therefore not, by themselves,
a migration blocker.
[Selected Spicetify builder](https://github.com/Gerg-L/spicetify-nix/blob/13e6fed4eb99f809d390fb50f591bed6cb716dc0/pkgs/spicetifyBuilder.nix)

SpotX must operate only on the writable derivation output, with pinned sources,
a temporary home, and networking denied during patching. `SPOTX_BUILD_MODE`
suppresses the live version check and process killing; it does not make installer
options safe. Keep path, forced-version, installation, rollback, uninstall,
clear-cache, force, interactive, and diagnostic/early-exit options outside user
arguments. Always supply `--noninteractive`, including for `spotxArgs = [ ]`.
Remove `--oldui`: both selected clients exceed its `1.2.13.661` upper bound.
[Current pinned SpotX parser and execution](https://github.com/SpotX-Official/SpotX-Bash/blob/db0583a456fab7b0488c92fd471e6a260e08b995/spotx.sh)

Keep `--devmode`, `--hide`, `--lyricsbg`, `--premium`, and `--noexp` as explicit
feature choices. `--premium` skips free-tier patches; it does not grant server
entitlements. `--noexp` skips SpotX's forced experiment rewrites. Spicetify's
`experimentalFeatures = false` controls its experiment editor, so it does not
substitute for `--noexp`. The checked-in package currently defaults to `--hide`,
`--noninteractive`, and `--nocolor`; this review does not reinterpret that UI
policy or infer an account tier.
[Current SpotX dispatch](https://github.com/SpotX-Official/SpotX-Bash/blob/db0583a456fab7b0488c92fd471e6a260e08b995/spotx.sh)
[Current root module](../../modules/home/spotify.nix)

Extensions execute JavaScript inside the client and can interact with its APIs.
Keep their sources pinned and their selection deliberate. The current utility
and metadata extensions remain a separate concern from replacing the package
recipe; a mutable Marketplace installer adds another update and trust path.
[Spicetify extension development](https://spicetify.app/docs/development/extensions)

### Darwin signatures and consent

Resource changes invalidate the vendor signature. Sign the finished bundle,
including nested code, after all resource modifications. Preserve the declared
runtime and entitlement policy until native evidence supports a change; a
successful build or an outer `CodeResources` file does not establish signature
validity. Native verification should include:

```sh
/usr/bin/codesign --verify --deep --strict --verbose=2 Spotify.app
/usr/bin/codesign --display --entitlements :- Spotify.app
/usr/bin/codesign --display --requirements :- Spotify.app
```

[Apple signing guidance](https://developer.apple.com/library/archive/technotes/tn2206/)

Both recipes replace vendor identity with an ad-hoc signature. Ad-hoc signing
provides integrity for a particular code instance; it supplies no signing
identity and does not preserve Spotify's Developer ID or establish notarization.
Apple explains that ad-hoc designated requirements are tied to the specific
code version. Therefore a package migration must not promise stable TCC consent
from a matching bundle name or identifier. Preserve application data, inspect
requirements and entitlements, and check relevant permission prompts on macOS.
Avoid activation-time bundle mutation or blanket TCC resets.
[Apple ad-hoc definition](https://developer.apple.com/documentation/security/seccodesignatureflags/adhoc)
[Apple designated requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/)

### Alternatives and licensing

Unmodified Spotify has the smallest customization maintenance burden. A signed
vendor macOS application also retains vendor identity if its sealed bundle stays
unchanged. Spotify plus Spicetify removes the SpotX patch layer and preserves
Spicetify themes and extensions, but still modifies the application and requires
final signing on macOS; it cannot preserve all SpotX behavior by substitution.
The shared Nixpkgs package already owns platform-specific Spotify acquisition.
[Selected Nixpkgs package](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/sp/spotify/package.nix)
[Spicetify builder](https://github.com/Gerg-L/spicetify-nix/blob/13e6fed4eb99f809d390fb50f591bed6cb716dc0/pkgs/spicetifyBuilder.nix)

Librespot and its clients change the product rather than replacing this recipe:
they do not run the Spotify desktop UI or Spicetify themes. Its maintained source
requires Premium and currently reports Spotify-side audio-key incompatibility
for some newer accounts. It is not a safe transparent replacement for this
configuration's desktop client.
[Librespot source, reviewed revision](https://github.com/librespot-org/librespot/blob/15e02e86c72d96dd39d548e3749f00abe39ffdde/README.md)

Keep `spotify-spotx` excluded from hosted builds and binary publication under the
existing project policy. Spotify's current guidelines restrict modification and
ad-blocking tools; its terms restrict redistribution. The MIT license on the
patcher's recipe does not license the Spotify application. Official SpotX-Nix's
workflow builds and uploads a patched macOS artifact, but that is not a grant of
permission for this repository to copy that policy. Switching to Spicetify alone
also does not resolve the client-modification question.
[Spotify guidelines](https://www.spotify.com/us/legal/user-guidelines/)
[Spotify terms](https://www.spotify.com/us/legal/end-user-agreement/)
[Official workflow](https://github.com/SpotX-Official/SpotX-Nix/blob/9902095a78f97520940cdf8eeb4093d6962dee9f/.github/workflows/check.yml)
[Project licensing policy](../../pkgs/docs/package-licensing.md)

### Native preload and Spicetify ad-blocking alternatives

Reviewed 2026-11-17 against the selected Nixpkgs and Spicetify sources. These
alternatives can reduce the SpotX-specific patch layer, but have different
platform coverage and behavior; neither inspected implementation is a transparent
replacement for the current complete variant.

| Alternative | Maintenance and version evidence | Platform and packaging implication |
| --- | --- | --- |
| `abba23/spotify-adblock` | Unarchived; current source `0f1873638f5dd0ccd62741a518bbe4ccc7670cf9`, dated 2026-08-14, declares 1.2.0. Latest published release is v1.1.1, dated 2026-08-12, with an explicit fix for Spotify 1.2.95.453. | Linux shared-library preload. It can avoid modifying Spotify's files for ad blocking, but does not supply the selected music-only Home UI, experiment defaults, Darwin updater patch, or Darwin packaging/signing. |
| `rxri/spicetify-extensions` `adblockify` | Current owner is `rxri`, with author credited as `ririxi`. Unarchived; source `5da6cf1bb723f9efd0177f5fa4f4673b9e0c0936`, dated 2026-09-10, adds Spotify 1.3.0 support. | Spicetify extension with Linux/macOS/Windows installation paths. Already available through the selected spicetify-nix pin, so a future experiment would not need a new package source or mutable Marketplace installer. |

The maintenance dates and releases are source observations, not a guarantee of
compatibility with every later client.
[Native current source](https://github.com/abba23/spotify-adblock/commit/0f1873638f5dd0ccd62741a518bbe4ccc7670cf9)
[Native release](https://github.com/abba23/spotify-adblock/releases/tag/v1.1.1)
[Extension compatibility commit](https://github.com/rxri/spicetify-extensions/commit/5da6cf1bb723f9efd0177f5fa4f4673b9e0c0936)
[Extension manifest](https://github.com/rxri/spicetify-extensions/blob/5da6cf1bb723f9efd0177f5fa4f4673b9e0c0936/manifest.json)

**Native preload.** Current Rust source interposes CEF's URL-request function and
returns no request for denylisted URLs. Published v1.1.1 also interposes DNS
resolution using an allowlist, so choosing the current unreleased source or the
published release changes the hook surface. The library uses `dlsym(RTLD_NEXT)`;
its configuration comes from the user's configuration directory or `/etc`.
A declarative Linux integration would therefore need a pinned Rust package,
declared configuration, and a launcher that supplies `LD_PRELOAD` specifically
to Spotify. That adds native code to the client process and CEF ABI compatibility
to review. It provides no macOS signed-bundle route.
[Current hook](https://github.com/abba23/spotify-adblock/blob/0f1873638f5dd0ccd62741a518bbe4ccc7670cf9/src/lib.rs)
[Release hook](https://github.com/abba23/spotify-adblock/blob/v1.1.1/src/lib.rs)
[Loader](https://github.com/abba23/spotify-adblock/blob/0f1873638f5dd0ccd62741a518bbe4ccc7670cf9/src/hook.rs)
[Configuration](https://github.com/abba23/spotify-adblock/blob/0f1873638f5dd0ccd62741a518bbe4ccc7670cf9/src/config.rs)

The actual shared Nixpkgs revision `b3cff76391a4867236cc135b69a928d873b9f6d0`
has no `spotify-adblock` package attribute: a read-only Nix evaluation of
`pkgs ? spotify-adblock` returned `false`, and its package source contains no
recipe for this project. There is consequently no selected recipe to reuse.
Upstream warns that its preload does not work with Snap. The selected Spotify
recipe extracts a Snap archive and launches its ELF outside Snap confinement,
so the archive format alone does not establish incompatibility. Runtime
compatibility with this wrapper remains untested.
[Native packaging notes](https://github.com/abba23/spotify-adblock/blob/0f1873638f5dd0ccd62741a518bbe4ccc7670cf9/README.md)
[Selected Spotify recipe](https://github.com/NixOS/nixpkgs/blob/b3cff76391a4867236cc135b69a928d873b9f6d0/pkgs/by-name/sp/spotify/linux.nix)

**Spicetify extension.** The selected spicetify-nix already pins the current
`rxri` revision and exports `extensions.adblockify`, with `adblock` retained as
an alias. Both the TypeScript source and the actual shipped `adblock.js` were
inspected. The extension discovers webpack/Rspack internals, changes local
product state, disables ad managers, clears slots and injects ad-related CSS.
It also writes four experiment overrides through local storage and Spotify's
remote-config APIs. Therefore `experimentalFeatures = false` does not prevent
this extension from changing experiment state. Initialization can retry every
100 ms without an overall bound when required client APIs remain absent.
[Selected extension definition](https://github.com/Gerg-L/spicetify-nix/blob/13e6fed4eb99f809d390fb50f591bed6cb716dc0/pkgs/extensions.nix)
[Selected source pin](https://github.com/Gerg-L/spicetify-nix/blob/13e6fed4eb99f809d390fb50f591bed6cb716dc0/pkgs/npins/sources.json)
[Shipped JavaScript](https://github.com/rxri/spicetify-extensions/blob/5da6cf1bb723f9efd0177f5fa4f4673b9e0c0936/adblock/adblock.js)

Its README explicitly excludes downloads, Very High quality, native lyrics and
Jams. The inspected code does not implement SpotX's full music-only Home filter
or native macOS updater patch. Adopting it can keep the existing Spicetify theme
and utility extensions, but preserving all selected SpotX behavior would require
additional reviewed replacements. Spicetify still changes app resources: the
existing final Darwin signing and consent review remain necessary.
[Extension limits](https://github.com/rxri/spicetify-extensions/blob/5da6cf1bb723f9efd0177f5fa4f4673b9e0c0936/adblock/README.md)
[Selected Spicetify builder](https://github.com/Gerg-L/spicetify-nix/blob/13e6fed4eb99f809d390fb50f591bed6cb716dc0/pkgs/spicetifyBuilder.nix)

**Recommendation.** Keep the current variant for this change. If reducing the
SpotX layer later becomes the priority, the already-pinned `adblockify` is the
smaller cross-platform experiment to evaluate before introducing a new Linux
preload package. Treat its experiment writes, retry lifecycle and missing UI/
updater behavior as explicit acceptance items. Keep the existing hosted-build
exclusion policy under review for any replacement: changing the implementation
does not itself resolve Spotify's ad-blocking or client-modification restrictions.
[Spotify guidelines](https://www.spotify.com/us/legal/user-guidelines/)

No alternative was built, installed, enabled or exercised against an account.
These are bounded source findings about the two inspected implementations, not
a claim that no other equivalent implementation exists.

## Validation and limits

This review inspected complete immutable upstream source files, the selected
local package sources and root integration. Both upstream source-archive hashes
were prefetched and verified on Linux. A private evaluation of the proposed
argument invariant returned `[ "--noninteractive" ]` for an empty feature list
and rejected `--oldui`. No new automated behavior suite was added.

No patched client was built, activated, or used for account access during this
research. No macOS launch, signing, TCC, Keychain, playback, or copy-app continuity
check ran. Earlier native signing results in the previous investigation are
historical evidence and do not validate current binaries or a migration.

## Implication for this repository

Apply the narrow argument repair and keep the current local package, final
signing policy, UI integration, and hosted-build exclusion. Revisit migration
when it can preserve the selected Darwin client without rebuilding the same
acquisition adapter, carry the local build restrictions and signing settings,
and pass native composed-app acceptance. Import a future official recipe into
`nixpkgs-personal` with an immutable source/hash; root integration should continue
to consume the ordinary `spotify-spotx` package attribute.
