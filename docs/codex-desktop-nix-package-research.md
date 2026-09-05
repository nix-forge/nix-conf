# Codex Desktop Nix package research

Research date: 2026-09-05 UTC

## Conclusion

Package OpenAI's native releases instead of trying to build the desktop app
from source. The application is a closed-source Electron product that embeds
the open-source Codex CLI, and OpenAI publishes first-party artifacts for all
three systems supported by this repository: `x86_64-linux`, `aarch64-linux`,
and `aarch64-darwin`. OpenAI also publishes an Intel macOS artifact, but this
repository deliberately does not evaluate `x86_64-darwin`.

The clean design is one package with platform-specific source records and two
installation paths:

- On Linux, extract the official `.deb`, retain the complete bundled Electron
  application, patch its native ELF dependencies with `autoPatchelfHook`, wrap
  it for the GTK runtime, and install its desktop file and icon.
- On macOS, copy the signed and notarized `.app` bundle without modifying any
  file inside it. Keep `dontFixup = true` and expose an external launcher.

Keep `openai-codex-desktop` as the Nix attribute and compatibility executable,
but also install the upstream `chatgpt` executable. The current product is the
ChatGPT desktop app with Chat, Work, and Codex modes, not a separately released
Codex-only application. [OpenAI's desktop app documentation](https://learn.chatgpt.com/docs/app)
and [OpenAI's product help article](https://help.openai.com/en/articles/9275200)
describe that combined product.

## Existing package assessment

The pre-change package in
[`pkgs/pkgs/by-name/op/openai-codex-desktop`](../pkgs/pkgs/by-name/op/openai-codex-desktop/)
was a sound minimal package for Apple Silicon: it fetched a fixed-output ZIP,
copied `ChatGPT.app` into `$out/Applications`, added a launcher symlink, avoided
fixup so that the signed bundle was not changed, and provided an appcast-based
updater. Its main limitations were:

- only `aarch64-darwin` had a source or package implementation;
- the source file assumed one global version and architecture;
- the updater knew only the Apple Silicon appcast;
- there were no package-contract checks for Linux desktop integration, ELF
  dependency closure, or macOS signature preservation;
- the metadata still described a Codex-only application.

The bundle-preservation behavior should remain. The source model, Linux build,
metadata, updater, and tests need to be expanded.

## Official artifacts and platform coverage

OpenAI's Linux preview supports Ubuntu 24.04 and 26.04, Debian 13, and Fedora 43
and 44 on both x64 and ARM64. It publishes `.deb` and `.rpm` downloads and
configures a signed package repository when those packages are installed.
[OpenAI's Linux installation guide](https://learn.chatgpt.com/docs/linux/linux-app)
is the authoritative support statement. The same guide says that XWayland is
the default display path, native Wayland is experimental, and Computer Use is
not yet available in the Linux preview.

OpenAI's macOS support article currently requires macOS 14 and supports both
Apple Silicon and Intel. [OpenAI's macOS requirements](https://help.openai.com/en/articles/9395554-what-are-the-system-requirements-for-the-chatgpt-macos-app)
are stricter than the current appcast's `minimumSystemVersion` value of 13.0;
package metadata should follow the documented support policy and avoid making
a stronger OS-version promise.

The first-party channels map to Nix systems as follows:

| Nix system | Artifact | Version discovery | Repository status |
| --- | --- | --- | --- |
| `x86_64-linux` | `chatgpt_<version>_amd64.deb` | signed APT `Packages` index | supported |
| `aarch64-linux` | `chatgpt_<version>_arm64.deb` | signed APT `Packages` index | supported |
| `aarch64-darwin` | `ChatGPT-darwin-arm64-<version>.zip` | Sparkle appcast | supported |
| `x86_64-darwin` | `ChatGPT-darwin-x64-<version>.zip` | x64 Sparkle appcast | upstream only |

The machine-readable channels are OpenAI's
[Apple Silicon appcast](https://persistent.oaistatic.com/codex-app-prod/appcast.xml),
[Intel appcast](https://persistent.oaistatic.com/codex-app-prod/appcast-x64.xml),
[amd64 APT index](https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages.gz),
and [arm64 APT index](https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-arm64/Packages.gz).
The APT repository also publishes a clear-signed
[`InRelease`](https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/InRelease).

At the research timestamp, all four channels advertised version
`26.901.41600`. The immutable Linux artifacts were:

| Architecture | SHA-256 in APT metadata | Nix SRI hash |
| --- | --- | --- |
| amd64 | `15cf422a77e8f28a7553d3180b8c72784a994438a141784c82d72cde93efca77` | `sha256-Fc9CKnfo8op1U9MYC4xyeEqZRDihQXhMgtcs3pPvync=` |
| arm64 | `8d5141b299ca593255fa25760895e84375937cc305197528c822dfa71ac2a3bf` | `sha256-jVFBspnKWTJV+iV2CJXoQ3WTfMMFGXUoyCLfpxrCo78=` |

Those hashes correspond to
[`chatgpt_26.901.41600_amd64.deb`](https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.901.41600_amd64.deb)
and
[`chatgpt_26.901.41600_arm64.deb`](https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.901.41600_arm64.deb).
The updater should select immutable pool URLs from the index, not package the
moving `/latest/` aliases.

An OpenAI maintainer has confirmed that the desktop application is not open
source and that it builds on the open-source Codex CLI's app-server APIs.
[OpenAI Codex discussion 16538](https://github.com/openai/codex/discussions/16538)
therefore rules out a reproducible source build of the official desktop app.

## Linux package anatomy

The official `.deb` is an Electron application, not Tauri. Its packaged
`package.json` identifies `openai-codex-electron`, product name `Codex`, and
Electron 42.3.0 for version `26.901.41600`. The payload contains:

- `/usr/lib/chatgpt/ChatGPT`, the Electron ELF executable;
- `resources/app.asar` and all renderer resources;
- architecture-specific Node native modules such as `better-sqlite3`,
  `node-pty`, `sharp`, `canvas`, HID, and filesystem watcher bindings;
- static PIE `codex` and `codex-code-mode-host` executables;
- `/usr/bin/chatgpt`, a symlink through `codex-launcher`;
- a `chatgpt.desktop` file and application icon;
- an AppArmor profile for the Debian installation path.

This is a native Linux release and should be packaged directly. Substituting
Nixpkgs' Electron runtime would couple the private app, its native modules, and
OpenAI's Electron integration to a different ABI. Retain the complete
`/usr/lib/chatgpt` tree instead.

Use `dpkg-deb -x` only to unpack the archive. Do not run its `postinst` script,
which installs OpenAI's signing key and APT repository. Install only the
application tree and desktop integration files into the Nix output; do not copy
the distribution-owned `/etc` files.

The main executable links against the expected Electron desktop stack: GTK 3,
GLib/GIO, ATK and AT-SPI, Cairo, Pango, GDK Pixbuf, NSS/NSPR, D-Bus, CUPS, ALSA,
udev, GBM/DRM, X11/XCB, XKB Common, OpenGL, and the C/C++ runtimes. A Linux
derivation should use `stdenv.mkDerivation`, `dpkg`, `autoPatchelfHook`, and
`wrapGAppsHook3` or an equivalent explicit wrapper. The initial native library
set should include the Nixpkgs equivalents of those dependencies and then be
trimmed only from actual `autoPatchelfHook` results.

The archive also contains prebuilt modules for multiple libc targets. Nixpkgs'
[`autoPatchelfHook` documentation](https://nixos.org/manual/nixpkgs/unstable/#setup-hook-autopatchelfhook)
explains its fail-closed dependency resolution. Its
[implementation](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/au/auto-patchelf/source/auto-patchelf.py)
skips static binaries and foreign architectures, but same-architecture musl
prebuilds may still require a narrow `autoPatchelfIgnoreMissingDeps` entry for
`libc.musl-*.so.*`. Do not use a broad ignore list.

Expose `xdg-utils` to the application at runtime for URL and file integration.
Provide Git as a fallback after the user's existing `PATH`, matching the Debian
package's recommendation without overriding the user's configured Git. Secret
storage is also a host integration concern. Electron's
[`safeStorage` documentation](https://www.electronjs.org/docs/latest/api/safe-storage/)
states that Linux may fall back to a weak `basic_text` backend when no supported
secret store is available, so the NixOS or Home Manager configuration should
provide a Secret Service implementation such as GNOME Keyring or KWallet.

## macOS signature and Gatekeeper behavior

The inspected Apple Silicon bundle had identifier `com.openai.codex`, a
Developer ID signature from OpenAI OpCo, LLC, hardened runtime, a secure
timestamp, and a stapled notarization ticket. It passed `codesign --verify` and
the local Gatekeeper assessment.

Apple explains that code signing lets macOS detect post-signing changes and
that notarization supplies additional trust information to Gatekeeper.
[Apple code-signing services](https://developer.apple.com/documentation/security/code-signing-services),
[Apple notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
and [Apple platform security's Gatekeeper description](https://support.apple.com/guide/security/sec5599b66df/web)
support preserving the upstream bundle exactly.

Use `cp -a` to retain the bundle's modes and symlinks, set `dontFixup = true`,
and never patch its plist, ASAR, Mach-O files, or embedded helpers. A launcher
or symlink outside `ChatGPT.app` does not alter its signature. Nix store copies
should not be assumed to preserve Finder quarantine extended attributes. Do not
manufacture or strip quarantine state as part of the derivation; the fixed Nix
hash and embedded upstream signature are separate integrity controls.

The build should verify the bundle non-destructively with
`codesign --verify --deep --strict`, check the expected bundle identifier and
version with `plutil`, and confirm the expected Mach-O architecture. Keep
`spctl` and launch checks out of deterministic build phases because they depend
on host policy and, at times, external trust services.

## Sandbox and display integration

There are two independent sandboxes:

1. Electron's Chromium renderer sandbox.
2. Codex's sandbox for commands and workspace access.

Do not disable either one as a packaging workaround. Electron documents the
renderer sandbox and warns that `--no-sandbox` is for testing only.
[Electron sandbox documentation](https://www.electronjs.org/docs/latest/tutorial/sandbox)
and [Electron command-line switches](https://www.electronjs.org/docs/latest/api/command-line-switches/)
are explicit on this point.

The Debian artifact ships an AppArmor profile granting `userns` to the
hard-coded `/usr/lib/chatgpt/ChatGPT` path. That path cannot match a Nix store
executable. Chromium's
[AppArmor user-namespace guidance](https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md)
explains why affected distributions need a path-specific policy. NixOS currently
defaults `security.allowUserNamespaces` to true in its
[`security.misc` module](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/security/misc.nix),
so no package-level `--no-sandbox` escape hatch is warranted. If a hardened
host later needs AppArmor policy, add a separate NixOS module whose attachment
path comes from the package output.

Do not force native Wayland flags. Preserve OpenAI's documented XWayland
default and allow users to opt into `--ozone-platform=wayland` while upstream
calls it experimental. This avoids turning a package improvement into an
unsupported display-mode change.

Codex's own workspace sandbox remains an application feature. OpenAI describes
the desktop app as using native system sandboxing and limiting access to
selected folders in its
[Codex app launch post](https://openai.com/index/introducing-the-codex-app/).
The package should not inject permissive flags or broad filesystem grants.

## Source model and updater

Represent sources by Nix system, with a version, immutable URL, and Nix hash in
each record. Even when all platforms have the same version, separate records
handle staged upstream rollouts without making an otherwise valid platform
unbuildable:

```nix
{
  x86_64-linux = { version = "..."; url = "..._amd64.deb"; hash = "..."; };
  aarch64-linux = { version = "..."; url = "..._arm64.deb"; hash = "..."; };
  aarch64-darwin = { version = "..."; url = "...-arm64-....zip"; hash = "..."; };
}
```

The updater should:

1. Fetch both Linux `Packages.gz` indexes and the relevant Sparkle appcast.
2. Require HTTPS, the exact `persistent.oaistatic.com` host, the expected
   package or enclosure name, and the matching architecture.
3. Select the immutable APT `Filename`, version, size, and SHA-256 rather than a
   `/latest/` URL.
4. Confirm that the fetched Linux artifact's Nix hash represents the exact
   SHA-256 published in the signed repository metadata. Verifying the
   `InRelease` signature against a pinned OpenAI fingerprint would strengthen
   the update pipeline further.
5. Validate the `.deb` control record and expected payload paths, plus the
   macOS bundle name and executable, before writing source data.
6. Write one fully rendered source file atomically and retain explicit
   `--check` and dry-run behavior.
7. Allow platform versions to differ temporarily.

The macOS build normally uses Sparkle to update itself, but an application in
the immutable Nix store cannot replace its own bundle. OpenAI's
[managed-update documentation](https://learn.chatgpt.com/docs/enterprise/manage-app-updates)
warns that administrators who disable automatic updates take responsibility
for rapid security updates and that old releases do not receive separate
security patches. Do not modify the signed app to suppress its updater. Run the
package updater on a frequent schedule, preferably weekly, and treat failures
as actionable maintenance signals.

## Metadata and package interface

Recommended metadata:

```nix
meta = {
  description = "OpenAI's ChatGPT desktop app with Codex";
  homepage = "https://learn.chatgpt.com/docs/app";
  downloadPage = "https://chatgpt.com/download/";
  license = lib.licenses.unfree;
  sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
  mainProgram = "chatgpt";
};
```

Nixpkgs documents these fields in its
[`meta.license`](https://nixos.org/manual/nixpkgs/unstable/#sec-meta-license),
[`meta.sourceProvenance`](https://nixos.org/manual/nixpkgs/unstable/#sec-meta-sourceProvenance),
and [`meta.platforms`](https://nixos.org/manual/nixpkgs/unstable/#var-meta-platforms)
sections. Use an exact platform list, not `lib.platforms.linux`, because OpenAI
does not publish artifacts for every Linux CPU or libc supported by Nixpkgs.

Install `$out/bin/chatgpt` as the canonical upstream command and keep
`$out/bin/openai-codex-desktop` as a compatibility symlink. The desktop file
should invoke `chatgpt %U` and keep upstream MIME handlers. Add
`passthru.updateScript = [ ./update.py ]` and expose cheap package checks through
`passthru.tests` where that improves local and CI discoverability.

## Verification plan

The package should have deterministic structural checks on each supported
system:

- Linux: validate the desktop file, icon, launcher, MIME handlers, app resource
  tree, and executable permissions; let `autoPatchelfHook` fail on unresolved
  native libraries; run the bundled `codex --version` as a non-GUI smoke test.
- macOS: check plist version, identifier, main executable, architecture, and
  `codesign --verify --deep --strict`; confirm that both launcher names resolve
  outside the untouched bundle.
- Updater: use local fixtures for appcast and APT index parsing, rejection of
  the wrong host/path/architecture, version-skew handling, and atomic writes.
- CI: evaluate and build the isolated package on `x86_64-linux`,
  `aarch64-linux`, and `aarch64-darwin`. Keep authenticated GUI launch, D-Bus,
  keyring, X11, and Wayland checks as separate host smoke tests.

The pinned Nixpkgs tree contains useful primary-source precedents:

- [`github-copilot-app`](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/gi/github-copilot-app/package.nix)
  has separate Darwin and Linux installation paths for an upstream desktop app.
- [`tana`](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/ta/tana/package.nix)
  packages a bundled Electron `.deb` with ELF patching and runtime paths.
- [`code-cursor`](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/co/code-cursor/package.nix)
  shows signed macOS bundle preservation and a narrow musl dependency ignore.

Nixpkgs' package test guidance recommends checks that are cheap enough to run
with the package rather than tests that require a full interactive desktop.
[Nixpkgs package tests](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md#package-tests)
supports that split.

## Recommended implementation order

1. Replace the global source record with per-system records and update the
   updater before changing the derivation.
2. Preserve the existing macOS copy path, compatibility launcher, and
   `dontFixup` behavior, then add signature and plist checks.
3. Add the Linux `.deb` extraction, explicit native libraries, GTK wrapper,
   desktop integration, and narrow auto-patchelf exception if the archive
   proves it necessary.
4. Update metadata and package exports for the repository's exact three-system
   matrix.
5. Add structural checks and updater fixtures, then build the isolated package
   on each native platform. Follow the repository rule that the full
   `nixosConfigurations.desktop` closure is built on the `desktop` host.
