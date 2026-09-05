# Spotify SpotX and Spicetify integration research

## Verdict

Use SpotX-Bash, not the Windows-focused SpotX PowerShell project, for both supported hosts. Patch a writable Spotify copy during the Nix build, run Spicetify after SpotX, and sign the finished macOS application once. Activation should only copy and register the already signed app.

The safe composition is:

1. Start with a fixed-output, hash-pinned Spotify package.
2. Run a commit-pinned SpotX-Bash with networking disabled.
3. Run the pinned `spicetify-nix` builder against the SpotX result.
4. On macOS, recursively ad-hoc sign the complete app bundle and verify it.
5. Remove SpotX backup files and reject outputs that lack the SpotX marker.

SpotX-Bash documents Linux and macOS support and directs NixOS users to build-time packaging because `/nix/store` is read-only. [SpotX-Bash README](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/README.md#L13-L62) [NixOS FAQ](https://github.com/SpotX-Official/SpotX-Bash/wiki/SpotX%E2%80%90Bash-FAQ#is-nixos-supported) Its companion [SpotX-Nix package](https://github.com/SpotX-Official/SpotX-Nix/blob/e9d738c5df3d47290090c891fa9828984c99c95e/nix/package.nix) establishes the same immutable build pattern on Linux, but only exposes `x86_64-linux`. A small local adapter is therefore appropriate for this repository's `x86_64-linux` and `aarch64-darwin` hosts.

## Paths and mutation order

| Platform | Spotify input | SpotX `-P` | Spicetify resource root | Final signing target |
| --- | --- | --- | --- | --- |
| Linux x86_64 | Nixpkgs Spotify | `$out/share/spotify` | `$out/share/spotify` | None |
| macOS arm64 | Pinned Spotify update archive | `$out/Applications` | `$out/Applications/Spotify.app/Contents/Resources` | `$out/Applications/Spotify.app` |

These roots follow SpotX's platform-specific path handling: Linux expects the directory containing `spotify` and `Apps`, while macOS expects the directory containing `Spotify.app`. [Linux discovery](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L338-L422) [macOS discovery](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L215-L238) They also match the pinned Nixpkgs layouts for [Linux](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/sp/spotify/linux.nix) and [macOS](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/sp/spotify/darwin.nix).

SpotX must run before Spicetify. SpotX requires the stock `Apps/xpui.spa`; Spicetify's backup step extracts that archive and its apply step replaces Spotify's `Apps` contents. [Spicetify backup source](https://github.com/spicetify/cli/blob/1f13f736163165234eef4fb792a03f9b5b732aa4/src/cmd/backup.go) [Spicetify apply source](https://github.com/spicetify/cli/blob/1f13f736163165234eef4fb792a03f9b5b732aa4/src/cmd/apply.go#L26-L98) Upstream states the same order in its [SpotX and Spicetify FAQ](https://github.com/SpotX-Official/SpotX-Bash/wiki/SpotX%E2%80%90Bash-FAQ#can-spotx-bash-and-spicetify-be-used-together).

The pinned `spicetify-nix` builder appends its work to the Spotify package's `postInstall`. [Builder source](https://github.com/Gerg-L/spicetify-nix/blob/a8adfd6f9f341dd586d5c06dda3bbfa21c6014e7/pkgs/spicetifyBuilder.nix#L20-L45) That makes package hooks a useful ordering boundary: SpotX belongs in the base package's `postInstall`, while macOS signing belongs in an explicit later phase.

## Build-safe SpotX invocation

The non-interactive build invocation should set `SPOTX_BUILD_MODE=true`, supply the package path explicitly, and use only declared feature switches. Build mode suppresses live version lookup and process killing, but installer switches can still download Spotify and must remain unavailable. [Build-mode handling](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L145-L163) [Installer paths](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L832-L942)

Recommended common arguments for this configuration are `--premium --noexp --noninteractive --nocolor`. The account is Premium, so `--premium` correctly skips free-tier-only patches. `--noexp` prevents SpotX's default opt-in to hundreds of Spotify experiments, which gives a less volatile and more reviewable UI. On macOS, also use `--blockupdates --skipcodesign`: Nix owns the client version, and SpotX must not sign before Spicetify changes the bundle. [Documented defaults and options](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/README.md#L30-L50)

Do not expose raw arguments. In particular, exclude installer, path, forced-version, rollback, uninstall, clear-cache, force, and signing-control options from user configuration. Leave `--devmode`, `--hide`, `--lyricsbg`, and `--oldui` off by default. They expand privileges or make opinionated UI changes, and old UI is rejected on modern Spotify versions. [Old UI version gate](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1155-L1166)

## macOS signing at build time

Every SpotX or Spicetify resource change invalidates Spotify's original signature. Apple seals almost all bundle resources and records nested code signatures in the outer resource envelope, so the outer app must be signed after every mutation. Apple recommends inside-out signing and says `codesign --deep` signing is only for emergency repair; `--deep` is appropriate for verification. [Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/)

The pinned Nixpkgs `rcodesign` 0.29.0 package is the practical Nix-native signer. With no certificate arguments, `rcodesign sign Spotify.app` creates an ad-hoc signature and recursively signs nested bundles, frameworks, and Mach-O files before sealing the outer bundle. It needs no private key, Keychain access, or network connection, so it can run in the sandbox after Spicetify. [Nixpkgs package](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/rc/rcodesign/package.nix) [rcodesign signing documentation](https://gregoryszorc.com/docs/apple-codesign/stable/apple_codesign_rcodesign_signing.html)

The final package should preserve Spotify's Electron/JIT entitlements, request the hardened-runtime flag, and confirm that signing created the outer `Contents/_CodeSignature/CodeResources` seal. Check the finished result on macOS with:

```sh
/usr/bin/codesign --verify --deep --strict --verbose=2 Spotify.app
```

Apple documents that command as the closest local check to Gatekeeper. `rcodesign 0.29.0`'s own `verify` command is unsuitable here: it labels itself buggy and rejects the ad-hoc CMS that its signer emits. An ad-hoc signature provides bundle integrity and loadability, but it is not Spotify's Developer ID signature and is not a new notarization. That distinction should remain explicit.

Testing against the current pinned Spotify payload found that `rcodesign` signed all nested bundles, including `Contents/Library/LoginItems/StartUpHelper.app`, retained the required JIT entitlements, and passed Apple's strict verifier. The signature also survived the exact Home Manager `copyApps` rsync flags. [Home Manager copy implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/targets/darwin/copyapps.nix#L123-L143) Activation-time `codesign`, `chmod`, and `xattr` repair can therefore be removed. LaunchServices registration is independent and may stay.

## Reproducibility and update contract

Pin both SpotX-Bash and the Spotify archive by revision and Nix hash. Do not use upstream's `curl | bash` entry point or any client-install option in a derivation. Set a temporary `HOME`, keep the builder offline, and make unexpected `curl` calls fail. On Linux, patch only the writable `$out` during the package build; never mutate an installed store path or use `sudo`.

Treat the SpotX maximum as a hard compatibility boundary. At commit `7bee478`, SpotX declares support through Spotify `1.2.98.301.gfcaeba72`, but a newer version only produces a warning and patching continues. Missing regex matches also do not necessarily fail the script. [Version checks](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L451-L490) [Patch match handling](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L720-L729) The Nix package must reject Spotify versions above the pinned SpotX maximum before patching.

Each atomic SpotX and Spotify update should pass these checks:

- Evaluate both platform packages and reject unsupported architectures.
- Build Linux on an `x86_64-linux` builder and macOS on an `aarch64-darwin` builder.
- Confirm the patched `xpui` payload contains SpotX's `//# SpotX was here` marker.
- Confirm Spicetify's theme and selected extensions are present after SpotX.
- Delete `spotify.bak` and `xpui.bak`; immutable outputs do not need rollback copies. [Backup creation](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L667-L686)
- Confirm that `rcodesign` produced the outer resource seal, then run Apple's strict recursive verification on macOS.

## Experimental controls and SpotX flag policy

The two experimental settings do different jobs. In pinned `spicetify-nix`, `experimentalFeatures` is a nullable Boolean. An explicit value wins; `null` enables the feature only when an installed extension declares that it needs it. The module writes the result to `experimental_features` in `config-xpui.ini`. [Module option and extension metadata](https://github.com/Gerg-L/spicetify-nix/blob/a8adfd6f9f341dd586d5c06dda3bbfa21c6014e7/modules/options.nix#L13-L25) [Generated setting](https://github.com/Gerg-L/spicetify-nix/blob/a8adfd6f9f341dd586d5c06dda3bbfa21c6014e7/modules/options.nix#L250-L300)

Spicetify CLI 2.44.0 uses that setting to inject `expFeatures.js`, add an Experimental features menu, and hook Spotify's remote-config resolver. The menu stores each chosen override in `localStorage` and sends changes through Spotify's remote-config debug API. Newly discovered flags start at Spotify's current value. This option does not turn every experiment on, grant server-side entitlements, or stop Spotify from assigning its own experiments. [Apply path](https://github.com/spicetify/cli/blob/v2.44.0/src/apply/apply.go#L75-L106) [Resolver hook](https://github.com/spicetify/cli/blob/v2.44.0/src/apply/apply.go#L559-L582) [Override storage](https://github.com/spicetify/cli/blob/v2.44.0/jsHelper/expFeatures.js#L1-L42) [Runtime override calls](https://github.com/spicetify/cli/blob/v2.44.0/jsHelper/expFeatures.js#L118-L207)

Keep `experimentalFeatures = false`. This prevents future extensions from enabling the editor implicitly, avoids persistent client state outside Nix, and removes a version-sensitive hook into Spotify internals. Enable it only for short-lived testing, with the expectation that unfinished or account-gated features may fail.

SpotX's `--noexp` works differently. The pinned general experiment table contains 179 candidate rewrites, although two are commented out, plus six Premium-only rewrites. The default path also forces one Home subfeed flag. `--noexp` skips the 177 active general rewrites, the six Premium rewrites, and that Home flag. It leaves SpotX's always-on patches and Spotify's server-selected values alone. [Patch dispatch](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1138-L1153) [Experiment tables](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1381-L1569) Using both `--noexp` and Spicetify `experimentalFeatures = false` is deliberate.

The pinned parser accepts the following relevant controls. [Complete option parser](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L23-L143)

| Flag | Recommendation and risk |
| --- | --- |
| `-P <path>` | Adapter-owned and required. Point it at the exact derivation output root. Never accept a user path. [Path handling](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L215-L238) |
| `-F <version>` | Adapter-owned when version discovery cannot run. It has no long alias and makes every patch gate trust the supplied value, so derive it only from the pinned Spotify source. [Version handling](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L431-L490) |
| `--noninteractive`, `--nocolor` | Always use. The first forbids prompts and conflicts with `-i`; the second only removes ANSI output. [Prompt handling](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L732-L788) |
| `-p`, `--premium` | Use for this Premium account. It skips free-tier product-state patches and CSS that hides download and Very High quality controls. Always-on patches still run. [Plan dispatch](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1138-L1144) |
| `-e`, `--noexp` | Use. It skips SpotX's forced experimental defaults, not its core patches or Spotify's remote experiments. |
| `-B`, `--blockupdates` | Always use on macOS. It patches the client updater, which must not replace the Nix-managed payload. Linux ignores it. [Update patch](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1181-L1184) |
| `-S`, `--skipcodesign` | Adapter-owned on macOS. It lets Spicetify run before final signing, but still calls `/usr/bin/xattr -cr`; neutralize that host call in the sandbox. [Signing function](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L952-L964) |
| `-d`, `--devmode` | Leave off. It adds native and UI patches that expose unsupported Spotify debug tools. Permit only as an explicit debugging choice. [Developer patch](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1145-L1148) |
| `-h`, `--hide` | Leave off unless the user wants a music-only Home page. It filters Podcast, Audiobook, and Episode items and adds hiding CSS. [Hide patches](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1152-L1171) |
| `-l`, `--lyricsbg` | Leave off. Its hard-coded black lyrics CSS competes with the declarative Spicetify theme. [Lyrics patches](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1172-L1180) |
| `-o`, `--oldui` | Reject. It works only through Spotify 1.2.13.661; current clients warn and ignore it. [Old UI gate](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1155-L1166) |
| `-f`, `--force`; `-c`, `--clearcache`; `--uninstall` | Reject. They restore old backups, delete user cache databases, or depend on backup files that this immutable package removes. [Force behavior](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L1005-L1035) [Cache deletion](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L966-L977) |
| `-i`, `--interactive` | Reject. It prompts for patch and installation choices and can select an installer. [Interactive choices](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L771-L788) |
| `--installdeb`, `--stable`, `--installmac`, `--rollback` | Reject. These download or install mutable clients; the Debian path can invoke `sudo`, `dpkg`, and `apt`. Nix fetchers must own downloads and hashes. [Linux installer](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L832-L873) [macOS installer](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L875-L950) |
| `--help`; `-v`, `--version` | Informational early exits. Keep them out of patch arguments; version output can perform a live lookup unless build mode is set. |
| `--debug`, `--logo`, retired `-V`, timestamp diagnostic token | Do not expose these undocumented maintenance paths. Logo exits immediately, `-V` errors, and the timestamp token unlocks internal regex diagnostics only with debug and developer mode. |

`SPOTX_BUILD_MODE=true` is an environment control, not a flag. It suppresses the live SpotX version request and process killing, but does not disable installer downloads. The adapter must still reject installer flags and block unexpected network tools. [Build-mode branches](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L145-L163) [Installer dispatch](https://github.com/SpotX-Official/SpotX-Bash/blob/7bee47814477d43287b2fbc2ac10b24db781969d/spotx.sh#L473-L507)

## UI and runtime defaults

Use one modification source for each job. SpotX supplies the client patches, while Spicetify supplies themes and small utility extensions. Remove Spicetify's `adblock` extension once SpotX is active on both platforms; it duplicates behavior and adds more runtime JavaScript to trust. Keep the existing `volumePercentage`, `shuffle`, `copyLyrics`, and `fullAlbumDate` extensions, which add visible utility without changing the package lifecycle.

Disable experimental features in both SpotX and Spicetify. Keep Marketplace and new third-party extensions as explicit, reviewed opt-ins because Spicetify extensions execute alongside the client and may call external services. [Extension security model](https://github.com/spicetify/docs/blob/d38162a3de28a8c0042e9a6b85432647d63d5394/docs/customization/extensions.md#L6-L30) The pinned `spicetify-nix` module already disables Spicetify's runtime update check, which is the right behavior for a declaratively updated package. [Generated configuration](https://github.com/Gerg-L/spicetify-nix/blob/a8adfd6f9f341dd586d5c06dda3bbfa21c6014e7/modules/options.nix#L280-L303)

This yields one immutable, reproducible client per platform, no activation-time signing, fewer overlapping patches, and an update failure when upstream compatibility is uncertain rather than a silently half-patched Spotify build.
