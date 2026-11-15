# Replacing the personal ChatGPT package with nixpkgs

Reviewed: 2026-10-12. Scope: official unified ChatGPT desktop application,
Linux x86_64 and arm64, and Apple Silicon macOS. No package, configuration,
PR, or issue was changed by this investigation.

## Answer

Current nixpkgs `chatgpt` is a credible replacement for the personal
`openai-codex-desktop` package, particularly on Linux. It is not uniformly
higher quality. Its broader Linux resource handling is stronger; the personal
package better preserves the caller's tools, signed macOS bundle, and update
metadata integrity. Adopt upstream after resolving the applicable migration
checks below. Retiring the whole personal package does not require every
optional upstream improvement to merge first.

The repository's locked nixpkgs is too old for this migration. Also, the
reviewed `nixos-unstable` snapshot has an older application than the personal
package. Distinguish package implementation quality from release freshness.

## Exact comparison

| Source | Revision or current working tree | Application version |
| --- | --- | --- |
| nixpkgs master | `f06e997db3ff435daf6f098b5e3199d1b16b8d5a` | Linux `26.1007.21434`; Darwin `26.1007.30912` |
| nixpkgs nixos-unstable | `7fd4004d0511991fff3a0524856a9be09e28c5f0` | `26.924.51851` on all three systems |
| Root flake's locked nixpkgs | `c59305bab2065cfecc4944690d9eedbb56f3a9fa` | Legacy Darwin-only implementation |
| Personal package | Working tree based on `8c4f1a824810fc5b7826e1183e7946752a7391fc` | Linux `26.1002.51308`; Darwin `26.930.61225` |

Both local repositories contain extensive pre-existing changes. This review
reads the current package files, including those changes, rather than assuming
the submodule commit alone describes the implementation.

Sources: [master package](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/by-name/ch/chatgpt/package.nix),
[master source records](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/by-name/ch/chatgpt/source.json),
[unstable source records](https://github.com/NixOS/nixpkgs/blob/7fd4004d0511991fff3a0524856a9be09e28c5f0/pkgs/by-name/ch/chatgpt/source.json),
[locked implementation](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/by-name/ch/chatgpt/package.nix),
[personal package](https://github.com/nix-forge/nixpkgs-personal/blob/584b4e67b026d45af616bd5700961b8217a357ee/pkgs/by-name/op/openai-codex-desktop/package.nix),
and [personal source records](https://github.com/nix-forge/nixpkgs-personal/blob/584b4e67b026d45af616bd5700961b8217a357ee/pkgs/by-name/op/openai-codex-desktop/source.nix).

The target is the first-party `chatgpt` package. `chatgpt-classic` and the
lencx web wrapper are different applications. Linux support merged October 11
in [PR #551713](https://github.com/NixOS/nixpkgs/pull/551713), followed by
[Darwin build repair #572863](https://github.com/NixOS/nixpkgs/pull/572863)
and [version update #572855](https://github.com/NixOS/nixpkgs/pull/572855).
This is a recently merged implementation, not a long-established Linux package.

## Where upstream is stronger

Upstream retains the vendor Electron runtime, patches native dependencies,
supplies GTK and Qt integration, and includes dynamically loaded audio,
Secret Service, PipeWire, OpenGL, and Vulkan libraries. It removes irrelevant
architecture prebuilds, musl Node modules on glibc, and the unused Qt5 shim
instead of keeping the personal package's wider missing-library exceptions.
Neither package adds `--no-sandbox` or wraps the entire app in an FHS namespace.
These observations come from the two package expressions; they do not prove
every optional integration works on every desktop.

The [upstream launcher](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/by-name/ch/chatgpt/launcher.nix)
provides a writable copy of all bundled plugins and exposes it through
`CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH`. It links the helper resources
into that layout, keys the cache by the entire store output, serializes
initialization, flushes writes before marking completion, and holds a shared
directory lock for cache cleanup. The
[tmpfiles rule](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/by-name/ch/chatgpt/tmpfiles.conf)
provides cleanup for unused resource caches. The personal launcher prepares
only the versioned browser plugin cache. Upstream's broader approach addresses
plugin-manifest writes and distinguishes differently patched outputs with the
same application version. This is a substantive reason to prefer upstream.

Upstream also packages Node, npm/npx, ripgrep, and Tectonic at the paths the
application expects. The personal README's assumption that an absolute bundled
Node path cannot be replaced by merely adding Node to PATH is correct, but
upstream additionally replaces that resource path and sets runtime overrides.
Therefore the earlier conclusion that these helpers necessarily need nix-ld
does not apply unchanged to upstream. Later arbitrary Python, Node, or native
downloads can still need host compatibility. Do not remove host nix-ld based
only on these substitutions. See the
[earlier runtime investigation](codex-desktop-nix-package-research.md).

The watcher crash is already addressed upstream by selecting the host libc in
`@parcel/watcher`, with ASAR extraction and repacking. The personal recipe
instead gives `detect-libc` the Nix ldd path. Both address the Electron report
fallback; the upstream fix is narrower and does not require discovering ldd.
The merged review records a
[successful Git-thread retest](https://github.com/NixOS/nixpkgs/pull/551713#issuecomment-5274086918).
Earlier PR comments about ineffective Wayland flags, missing npm/npx,
missing Tectonic, and deleting active caches concern superseded code. Do not
open duplicate repairs for them.

## Differences that matter before migration

### Caller PATH precedence

The personal launcher adds Git, bubblewrap, and optional tools as PATH
fallbacks. Upstream uses `--prefix PATH` for Git Minimal, Node/npm, coreutils,
and desktop helpers. Consequently subprocesses begin with upstream's Git and
Node ahead of the caller's versions. Existing Git configuration may still
apply, but a configured Git executable, wrapper, or project Node can change.
This difference is explicit in the package wrappers; it is not a demonstrated
failure of ordinary Git operations. The private app may hydrate its environment
later, so a full task must confirm final command selection.

For this configuration, preserve caller precedence for general development
tools before declaring the migration equivalent. A focused upstream PR could
suffix those PATH entries while retaining explicit Node overrides for the
app's own browser and REPL. Test conflicting caller Git/Node and a minimal PATH,
including npm/npx MCP startup. Do not remove required sandbox helpers.

### Frontend and backend version pairing

Upstream replaces both bundled `codex` and `codex-code-mode-host` with
[nixpkgs Codex](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/by-name/co/codex/package.nix),
currently `0.162.1`, and defaults `CODEX_CLI_PATH` to it. The source-built CLI
and its code-mode companion share a build commit and have Nix-specific resource
integration. This has maintenance benefits. It also decouples the frontend
from OpenAI's shipped backend and includes a patch disabling daemon auto-start
by default. The ChatGPT install check does not establish protocol compatibility.

No protocol failure was reproduced. A backend-default-change PR would be
premature without one. For the first migration, the existing
`pkgs.chatgpt.override { codex = null; }` option retains the vendor Codex pair.
It still replaces Node, ripgrep, and Tectonic, so it does not restore the entire
vendor payload. Compare both modes using app-server initialization, local
tasks, code-mode execution, browser work, voice if used, and remote sessions.
Direct bundled-CLI sandbox probes must also pass with bubblewrap absent from
the caller PATH; upstream does not wrap that bundled executable as the personal
package does. The default source-built CLI has its own packaged sandbox support.

### Signed Darwin bundle preservation

Upstream disables Darwin ELF and shebang patching but sets `dontStrip = isLinux`.
Darwin stripping therefore remains enabled. The
[strip hook](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/build-support/setup-hooks/strip.sh)
recurses into `Applications`, and
[Darwin stdenv](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/stdenv/darwin/default.nix)
sets debug strip flags to `-S`. The personal derivation explicitly uses
`dontFixup = true` to preserve the vendor bundle.

Upstream does not guarantee signed-bundle byte preservation. Actual signature
damage remains unverified without a native macOS build and comparison. Before
migrating macOS, compare vendor and output bundle bytes and run
`codesign --verify --deep --strict` on both. The preferred upstream change is
to disable stripping of the signed bundle and add non-mutating identity,
version, architecture, and signature checks. Keep the external launcher
available. Adding `meta.mainDarwinApp = "ChatGPT.app"` is useful metadata but
is secondary to preserving the bundle.

The current personal install check verifies plist and declared files; its
separate contract check contains signature-oriented validation. Do not describe
the ordinary personal build as proving full signature validity by itself.
See [personal Darwin recipe](https://github.com/nix-forge/nixpkgs-personal/blob/584b4e67b026d45af616bd5700961b8217a357ee/pkgs/by-name/op/openai-codex-desktop/darwin.nix)
and contract check at `pkgs/flake/dev/scripts/codex-desktop-darwin-contract.sh`.

### SSH workaround and host integration

The configuration has a separate
child-exit and SSH workaround at `overlays/temporary/codex-linux-child-exit.nix`.
Its reviewed source hashes and version boundary do not cover upstream's newer
artifact. Replacing the bundled CLI does not automatically repair Electron's
SSH command builder. Run the existing
[startup probe](../../tests/codex/check_ssh_startup.py) and a fresh multiplexed
SSH completion probe before dropping or porting the workaround. Earlier
[SSH research](codex-linux-ssh-startup-research.md) documents why a connection
that reuses an existing master can produce a misleading pass.

OpenAI still calls native Wayland experimental. Both recipes opt into it when
`NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are set, so the earlier note's stronger
claim that the custom recipe preserves XWayland by default is no longer an
accurate description of its current code. Upstream's launcher does not include
the personal wrapper's `WebRTCPipeWireCapturer` feature flag. Test portal screen
sharing if required; absence of that flag alone does not prove failure in the
current Electron runtime. NixOS is outside the vendor's formally supported
distribution list. [OpenAI Linux documentation](https://learn.chatgpt.com/docs/linux/linux-app)
and [sandbox prerequisites](https://learn.chatgpt.com/docs/sandboxing).

## Proposed upstream PRs

| Priority | Proposed change | Evidence and acceptance |
| --- | --- | --- |
| Before macOS migration | Preserve signed Darwin bundle and add checks | Strip traversal is enabled in source. Compare bytes and signatures before and after the fix on Apple Silicon macOS. |
| Before equivalent development-tool behavior | Preserve caller Git/Node precedence | Upstream prefixes PATH, personal suffixes it. Verify selected caller tools and fallback availability, plus bundled runtime consumers. |
| Maintenance improvement | Validate and atomically publish update metadata | Compare APT SHA256/Size, inspect downloaded Debian Package/Version/Architecture, validate URL shape, write temporary JSON then rename. Add wrong-artifact and interrupted-write fixtures. |
| Optional resilience | Validate cached plugin completeness and repair missing files | A disposable launcher probe reproduced persistent missing files behind `.complete`. Add structural repair checks under initialization locking, preserving valid mutable manifests. |
| Follow-up test coverage | Discoverable launcher and backend smoke tests | Test cache initialization/concurrency/cleanup, arguments, caller environment, sandbox enforcement, desktop entry, and compatible app-server initialization. Avoid an authenticated GUI requirement for deterministic package builds. |

The [upstream updater](https://github.com/NixOS/nixpkgs/blob/f06e997db3ff435daf6f098b5e3199d1b16b8d5a/pkgs/by-name/ch/chatgpt/update.sh)
computes fixed hashes for downloaded artifacts but does not compare Linux bytes
with APT SHA256/Size or inspect downloaded control records. Its final
`jq > source.json` write is not atomic. The
[personal updater](https://github.com/nix-forge/nixpkgs-personal/blob/584b4e67b026d45af616bd5700961b8217a357ee/pkgs/by-name/op/openai-codex-desktop/update.py)
already checks these artifact properties and uses atomic publication. These
are justified updater improvements, not evidence that the current upstream
hashes are wrong or unsafe. Both pipelines could go further by cryptographically
verifying repository metadata. Validating the presence and length of a Sparkle
signature, as the personal updater does, is not signature verification.

The current APT indexes each contain one package stanza. Upstream's first-field
parser works for those feeds. Multi-stanza selection is future hardening rather
than a present failure. A title-filtered GitHub search found no open ChatGPT
packaging PR, but it cannot rule out every related issue or PR. Recheck before
submitting anything. No PR or issue was opened.

## Migration work in this repository

1. Select a reviewed nixpkgs revision with Linux support and the desired
   application release. Updating unrelated inputs is not required merely to
   inspect or try the package. The pinned unstable snapshot above is older than
   the custom application despite having the new recipe.
2. Change the [home module](../../modules/home/dev/agentic-gui/codex-app.nix)
   to select `pkgs.chatgpt`. Upstream has no `extraPackages` argument. Preserve
   its current fallback-tool interface with an external wrapper if needed.
3. Update the
   [Stylix availability gate](../../modules/shared/stylix/targets/codex-desktop/home.nix),
   which currently checks the personal flake output. Keep the existing settings
   ownership and state paths.
4. Reassess the [package overlay](../../overlays/packages.nix) and registered
   SSH fix against the newly selected artifact. Do not blindly reuse its ASAR
   layout or remove its review guards.
5. Keep the desktop file integration on Linux. Darwin exposes `ChatGPT`, while
   the personal package exposes `chatgpt` and `openai-codex-desktop`. Audit CLI
   consumers and supply compatibility aliases if needed. The app bundle remains
   named `ChatGPT.app`, so Dock bundle-name references need no rename.
6. Build isolated packages and run the migration probes. Only then retire the
   personal recipe, updater, catalog entry, and related checks. Remove host
   compatibility or operational workarounds only after their own removal tests.

## Validation and limits

- Read current local package, helper, updater, integration, and SSH workaround
  sources. Read pinned upstream package, launcher, updater, source records,
  Codex recipe, Darwin stdenv, and strip hook, plus PR history and review evidence.
- Retrieved both live vendor APT indexes with a curl user agent. Linux
  `26.1007.21434` metadata digests match master source records on both architectures.
  The background source investigation also checked the Darwin appcast. An initial
  default urllib user-agent request received HTTP 403; the retry succeeded.
- Ran the exact upstream launcher's extracted shell body against disposable
  resources and a fake app. Initialization, writable plugin copies, helper
  links, argument preservation, and Wayland opt-in passed. Deleted a plugin
  service file after initialization; the next launch did not repair it because
  `.complete` remained. This is a shell-level reproduction, not a full packaged
  Electron or browser test.
- Requested an isolated x86_64 Linux build through `workstation-task`. It waited
  behind unrelated workstation jobs and was cancelled before execution. No
  package build result is claimed. No authenticated GUI launch, backend protocol
  comparison, fresh remote SSH probe, native ARM build, macOS build, signature
  comparison, system rebuild, or activation ran.
- The research note passed rumdl, typos, relative-link and whitespace checks,
  and a focused Gitleaks scan using the repository publication policy.

The outstanding adoption evidence is specific: Linux package build and local
task/browser/sandbox/SSH checks; caller tool selection; and native macOS bundle
preservation. Updater hardening and cache self-repair can follow adoption if
those required checks pass. The research supports a controlled migration to
upstream, not an unconditional claim that its defaults improve every workflow.
