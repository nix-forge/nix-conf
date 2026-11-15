# Overlay and patch review

Reviewed September 21, 2026 against the root flake pins and the checked-out
`pkgs/` submodule; package ownership was updated September 23. The inventory
covers active root overrides, root patch files, and package patches in
`nixpkgs-personal`. Evaluation and a running process do
not establish that every user interaction works.

## Hyprshell failure

The desktop runs Hyprland 0.56.0 and Hyprshell 4.10.8. A live
`check_alt_tab_release_race.py` run failed to focus the expected recent window.
The service logged `Failed to collect data: loading hyprland data failed` and
`missing field id`. The compositor's `monitors all` response has an empty
`specialWorkspace` with `address`, `type`, and `name`, but no `id`. Hyprshell's
bundled `WorkspaceBasic` parser requires `id`. [Hyprshell issue #523](https://github.com/H3rmt/hyprshell/issues/523)
reports the same protocol break, and the upstream development branch still
requires that field. [Hyprland PR #16140](https://github.com/hyprwm/Hyprland/pull/16140)
changed workspace identities.

The new [local parser patch](../../overlays/temporary/patches/hyprshell-empty-special-workspace.patch)
maps a missing workspace ID to the existing invalid sentinel, `-1`. The live
Alt+Tab check exercises monitor parsing through Hyprshell. Its [temporary fix record](../../overlays/temporary/hyprshell-workspace-schema.nix)
tracks the selected Hyprland revision separately from the older modifier timing
patch. This is a compatibility fix for the current pin. An upstream contribution
should handle the full address-based workspace protocol and add monitor fixtures
for empty and occupied special workspaces. The local sentinel alone is too narrow
for that upstream change.

The [modifier timing patch](../../overlays/temporary/patches/hyprshell-modifier-state.patch)
is still relevant to the separate release-order problem. Its upstream
[PR #521](https://github.com/H3rmt/hyprshell/pull/521) and prerequisite
[PR #522](https://github.com/H3rmt/hyprshell/pull/522) remain open. The pinned
release contains neither. Do not open a duplicate modifier PR.

## Root override decisions

The [temporary registry](../../overlays/temporary/default.nix) has a revision guard
for each fix. All listed pins matched at this review. A matching guard establishes
only that the selected input has not changed since its last review. The
`temporary-package-fixes` check evaluated all supported platforms and passed.

| Fix | Current decision | Upstream or removal evidence |
| --- | --- | --- |
| `actual-server-case` | Keep | Unpatched selected and current-master native Darwin builds fail on the theme import; the patched builds pass. |
| `claude-code-sandbox` | Keep the narrow sandbox override | Unpatched native Darwin build is rejected for `__noChroot`; with that setting removed, the install check and version check both pass. The old `doInstallCheck = false` override was removed. |
| `deploy-rs-darwin-tests` | Keep | Unpatched native Darwin build times out in the three skipped watcher tests; the selected package passes. A hermetic test backend needs upstream design. |
| `determinate-darwin-tests` | Keep | Unpatched native Darwin build fails in the Crashpad Sentry test and a libgit2 case-path test dependency; the selected package builds. |
| `determinate-sentry-module` and `sentry-crashpad-lock` | Keep | The NixOS module selects the repaired Nix input; the repository has contention and real-error checks. |
| `gtksourceview-xvfb` | Keep | The Virt Manager dependency alone receives the Xvfb lifecycle repair. |
| `hypridle-condition-inhibitors` | Keep | The package runs the retry and D-Bus inhibitor regression during its build. The patched daemon is running. |
| `hyprland-portal` | Keep | The selected portal still receives the GCC compatibility patch. |
| `hyprland-subsurface` | Keep | The patched compositor is running; prior native and protocol regression results are in [local fixes](../operations/hyprshell-hyprland-local-fixes.md). |
| `hyprshell-modifiers` | Keep | [PR #521](https://github.com/H3rmt/hyprshell/pull/521) is open; the current package remains v4.10.8. |
| `hyprshell-workspace-schema` | Keep | [Issue #523](https://github.com/H3rmt/hyprshell/issues/523) is open; current development source still requires `id`. |
| `nh-darwin-home` | Keep for v4.4.2 | [PR #758](https://github.com/nix-community/nh/pull/758) merged, but the selected version is still 4.4.2. The fix skips newer versions. |
| `nom-quadratic-build-plan` | Keep for v2.2.0 | [PR #304](https://github.com/maralorn/nix-output-monitor/pull/304) is open; the selected version is 2.2.0. |
| `prismlauncher-darwin-tests` | Keep pending native Darwin build | PrismLauncher is 11.1.0, but this patch concerns the sandbox watch test, not its release version. |
| `stylix-nvf` | Keep | [PR #2497](https://github.com/nix-community/stylix/pull/2497) and [PR #2499](https://github.com/nix-community/stylix/pull/2499) are open. A third PR would duplicate them. |
| `stylix-rofi` | Keep | [PR #2501](https://github.com/nix-community/stylix/pull/2501) is open for the renamed Rofi option. |
| `swift-wrapper-hardening` | Keep pending native Darwin probe | The selected Swift toolchain is 5.10.1; the wrapper probe checks compiler hardening flags. |
| `zen-wrapper-copy` | Keep | The wrapper repair only applies to Zen on the native builder. |

The [permanent overlay](../../overlays/default.nix) selects Determinate Nix,
exposes the personal package set, and selects region-only Grimblast from
`nixpkgs-personal`. Those choices encode intended configuration behavior. The local
[Ghostty Bash patch](https://github.com/nix-forge/nix-conf/blob/ac25d4952fcc432a49a838fd3ba4e48a913fd00b/overlays/temporary/patches/ghostty-bash-ble-prompt.patch)
remains outside the overlay: [upstream PR #11644](https://github.com/ghostty-org/ghostty/pull/11644)
merged, but this configuration still selects Ghostty 1.3.1 and the patch is
version-gated to that release. Patch files
under `docs/assets/`, `pkgs/docs/`, and `tests/` are evidence or test inputs,
not package overrides.

## nixpkgs-personal patch decisions

On September 23, the AudioMuse-AI Navidrome v10 release and loopback permission
repair moved from temporary root overrides into
`navidrome-plugin-audiomuseai-personal`. The region-only Grimblast variant moved
from the permanent root overlay into `grimblast-region`. Their package recipes,
source pins, and build checks now live in `nixpkgs-personal`.

These patches make named package variants. Their source pins and package names
remain explicit, so a newer unrelated Nixpkgs package does not automatically
replace them.

| Package | Patch files | Decision |
| --- | --- | --- |
| `hyprlock-personal` | `authentication-controls.patch` | Keep the optional submit and authentication UI behavior; Hyprlock 0.9.6 variant is running. Native lock interaction was not retested here. |
| `noctalia-greeter-personal` | `authentication-ux.patch` | Keep; recipe guards the expected 1.5.0 source. Greeter runtime was not tested here. |
| `noctalia-personal` | `symbolic-bar-icons`, `tray-icon-size`, `media-player-selector`, `readable-control-colors`, `home-calendar-card`, `workspace-strip` | Keep these intentional UI features. The pinned 5.1.0 variant is running and its build includes the bar icon policy test; individual interactions were not retested here. |
| `vorssaint` | `fan-helper-concurrency`, `swift-5.10-concurrency` | Keep. The latter is conditional on Swift older than 6; the selected Darwin toolchain is 5.10.1. A native Darwin build is still required to prove both patches. |

Update, 2026-10-01: the shared Nixpkgs pin now provides Swift 6.2.4. A native
Darwin build of Vorssaint 3.3.5 succeeded with the Swift 5.10 patch skipped,
so the obsolete patch and version guard were removed. The
`fan-helper-concurrency` patch remains. The Swift Clang importer hardening
probe also passed with the updated temporary wrapper.

## Validation and next upstream work

The desktop service inventory had no failed units. Noctalia, Hypridle, and
Hyprlock processes were running. This is a limited health signal, not a full
application test. The package audit did not find a confirmed upstream fix already
present in the selected source that justified removing an active patch.

On the desktop host, the revised Hyprshell 4.10.8 package built and its four
existing modifier timestamp tests passed. A trace of the revised daemon shows
monitor and client collection completing without the earlier parsing error and
the expected client being selected. After unlocking the session, the live
package check passed its release-order cases and 200 timed Alt+Tab chords;
each selected the expected window without leaving an overlay. The earlier
failure while Hyprlock held the session lock was also reproduced with a direct
Hyprland focus command. `just temporary-fixes-check` passed on the final
registry, and `just os-build desktop` built the complete desktop configuration.
In `pkgs/`, `just check` passed evaluation for supported systems and `just test`
built its package policy, independence, and unit checks. A full root
`nix flake check --no-build` was killed by the desktop memory limit during
output traversal, after many outputs evaluated successfully. It is not a pass.

`just os-switch desktop` rebuilt the configuration but could not activate it:
`sudo` required a password terminal. The running user service was restarted
with a runtime systemd override selecting the tested Hyprshell store path. The
override is active for this login session; a privileged system switch is still
needed to make the configuration the boot default.

A focused Hyprshell parser PR against its development branch is worthwhile if it
implements the address-based workspace model and reproduces issue #523 with a
fixture. The existing modifier PRs, `nh`, `nom`, and Stylix already have upstream
work; helping those reviews is more useful than opening duplicates. The local
Hyprland subsurface and Hypridle fixes are candidates for separate upstream PRs
with their existing regressions, after rebasing and validating against current
upstream. A previous [Hyprland ancestry PR #15446](https://github.com/hyprwm/Hyprland/pull/15446)
closed without merging, so a new submission should explain the newer teardown
tests and check maintainer expectations first. The earlier
[Swift wrapper PR #340586](https://github.com/NixOS/nixpkgs/pull/340586) also
closed without merging after its author reported a build failure; the local
native hardening probe would be useful evidence for a revised proposal once a
Darwin build passes. Package-specific UI variants should only be proposed
upstream when their maintainers want the behavior and its tests.

## Upstream contribution decisions, September 24

This follow-up checked current upstream heads as well as selected pins. No
active patch met the repository's removal test. A fix on an upstream development
branch does not retire a patch against the older source still selected here.

| Change | Upstream path and next step |
| --- | --- |
| Hyprland subsurface lifetime | Current [`main`](https://github.com/hyprwm/Hyprland/commit/e368c13c27a42a173b9e08fa0bf413f9f7073187) still has the unsafe walks. A two-commit candidate exists on the preserved `subsurface-local-validation` fork branch. Rebase in a clean worktree, show Hyprtester failure before the repair and success after it, and link the overlapping [closed, unmerged PR #15446](https://github.com/hyprwm/Hyprland/pull/15446). The old-base branch is not ready to open unchanged. |
| Hypridle condition retry | Current [`main`](https://github.com/hyprwm/hypridle/blob/aa958ed7ad4863860b93ecd7189419e193bfae2c/src/core/Hypridle.cpp#L264-L280) still retries without checking inhibitors. Port the narrow guard and regression upstream, then demonstrate a D-Bus inhibitor active during a pending retry in a separate bug-fix PR. |
| Hyprland portal compiler patch | Current [CMake flags](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/e87ae7823e7bf0601385220c69b5a3b245123fc5/CMakeLists.txt#L40-L50) still contain the unconditional Clang-specific flag, but [PR #432](https://github.com/hyprwm/xdg-desktop-portal-hyprland/pull/432) rewrote the picker. Separate the remaining GCC failure from stale cleanup hunks and run a current GCC build before proposing a fix. |
| Hyprshell modifier release | [PR #521](https://github.com/H3rmt/hyprshell/pull/521) already carries the developed fix and depends on [PR #522](https://github.com/H3rmt/hyprshell/pull/522). Both remain open. Rebase and rerun current checks before adding one factual update to #522. A status-only reminder or duplicate PR adds little. |
| Hyprshell workspace parsing | [Issue #523](https://github.com/H3rmt/hyprshell/issues/523) is acknowledged but has no upstream fix. The local missing-`id` sentinel handles only one case. A PR should update the vendored Hyprland data model for `address` and `type`, retain older data if supported, and test normal, occupied-special, and empty-special monitor objects. |
| Noctalia workspace IPC | The local patch still serves pinned 5.1.0. Upstream [commit `960d4d46`](https://github.com/noctalia-dev/noctalia/commit/960d4d46bd3149a556504e7c40ecd87abb251a36) implements a fuller fix with tests. Do not submit a duplicate. Retire the patch after updating the source pin and passing the unpatched build and runtime check. |

Hyprland's [AI policy](https://github.com/hyprwm/.github/blob/main/policies/AI_USAGE.md)
allows assisted local code with human understanding and disclosure, but bars
AI-authored developer-channel interaction. Its [PR template](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/.github/pull_request_template.md)
says unvouched new contributors are automatically closed. A human needs to
review the final code, establish eligibility, and write and submit any PR.

### Noctalia and Hyprlock features

The Noctalia patches should not become one PR. Its [contribution guide](https://github.com/noctalia-dev/noctalia/blob/main/CONTRIBUTING.md)
requires the PR template, `just format`, appropriate tests, English-only source
translation edits, and user documentation for new settings. Its
[ethos](https://noctalia.dev/ethos) favors small changes with clear motivation.

| Local patch | Best upstream route |
| --- | --- |
| `symbolic-bar-icons` | Coordinate with open [taskbar PR #4553](https://github.com/noctalia-dev/noctalia/pull/4553), which overlaps. Propose active-window behavior separately after rebasing. Keep tray overrides and status-icon policy separate from both. |
| `tray-icon-size` | A narrow tray-rendering PR is plausible. Show size-specific vector icons at multiple output scales and prove attention icons, overlays, and bitmaps retain their behavior. |
| `media-player-selector` | Start with an issue or design discussion. The large local patch replaces much of the Control Center media tab, removes its visualizer and other controls, and changes MPRIS behavior. [Issue #4542](https://github.com/noctalia-dev/noctalia/issues/4542) already requests an optional visualizer toggle. Agree on a configurable multi-player view, then submit model and UI changes in reviewable increments with multi-endpoint tests. |
| `readable-control-colors` | Propose a focused accessibility fix with contrast measurements across built-in light and dark palettes and interaction-state checks. The hard-coded alpha changes in shared controls may need a palette-aware design. |
| `home-calendar-card` | [Issue #3745](https://github.com/noctalia-dev/noctalia/issues/3745) explicitly asks for the disabled-weather and calendar-click behavior. Offer the focused change there, then add state tests. |
| `workspace-strip` | Treat as an optional appearance setting. [Issue #4281](https://github.com/noctalia-dev/noctalia/issues/4281) concerns taskbar sizing, but does not establish agreement on this exact styling. Ask for design direction and show before/after images at several scales. |
| `workspace-ipc-compat` | Already fixed more completely on upstream `main`; no new PR. |
| Greeter `authentication-ux` | Split the large patch into independently useful authentication feedback, keyboard and clock display, power confirmation, and scaling/layout changes. Check current `main`, add configuration docs and examples, and follow the [greeter contribution guide](https://github.com/noctalia-dev/noctalia-greeter/blob/main/CONTRIBUTING.md). Real greetd authentication and scaled-output checks matter. |
| Hyprlock `authentication-controls` | [Issue #997](https://github.com/hyprwm/hyprlock/issues/997) already proposes pointer submission through `submit_on_click`. Align the native action with that request and existing clickable widgets. Keep icon, hover, status, and PAM UI additions separate. Test empty-input policy, rapid clicks during PAM, keyboard parity, and a real lock session. The selected Hyprlock source is current upstream head, so the patch cannot be removed. |

The remaining fixes mainly belong to packaging or existing upstream work.
Keep the merged [`nh` PR #758](https://github.com/nix-community/nh/pull/758)
backport until the selected package contains it. Follow the open
[`nix-output-monitor` PR #304](https://github.com/maralorn/nix-output-monitor/pull/304)
and Stylix [#2497](https://github.com/nix-community/stylix/pull/2497) and
[#2499](https://github.com/nix-community/stylix/pull/2499) and
[#2501](https://github.com/nix-community/stylix/pull/2501) instead of opening
duplicates. The Darwin test and wrapper changes need native sandbox evidence
before proposals to their package owners. The Determinate and Sentry changes
need a clear split between NixOS module selection and Crashpad behavior.
Personal package variants can remain local when upstream does not want their
policy; a local variant is not itself a bug.

The initial audit inspected sources, PRs, issues, contribution rules, pins,
and local branches. Later preparation on September 24 rebased candidate
branches and built selected packages on Linux and native aarch64-darwin. Those
checks do not replace compositor, greeter, or visual interaction review.

## Follow-up review, October 4

This review uses the current working trees, including pending package and host
changes. Earlier decisions above describe their review dates. Merged PRs were
compared with the selected source or release before removing patches. The
external authored-PR search covered 90 results outside the configuration
organization and owner repositories. The review also covered all 220 authored PRs
in `nix-forge/nixpkgs-personal` and `nix-forge/nix-conf`: 196 merged and 24 closed
without merging, with none open. Unrelated CI PRs were not patch evidence.

### Retirements and narrower fixes

- Helium's upstream [installer repair](https://github.com/schembriaiden/helium-browser-nix-flake/commit/2f6586322d82beb2a50b01b129dea7dd7895d925)
  is included in input `1c8b387197ee1c9191c4bb8be9eb4c66eca5e795`, packaging
  0.18.2.1. The unmodified aarch64-darwin package built successfully. The temporary
  installer record and input wrapper were removed.
- Noctalia moves from 5.1.0 to 5.2.1. [Calendar PR #4578](https://github.com/noctalia-dev/noctalia/pull/4578)
  and the workspace IPC repair are included upstream. Their local patches were
  removed. The symbolic-icon, tray and workspace-strip patches were adapted to
  the new settings registry, icon resolver and workspace API. Other intentional
  appearance and player changes remain.
- Actual 26.10.0 removes the `Themes`/`themes` collision. The update matches
  [Nixpkgs PR #569583](https://github.com/NixOS/nixpkgs/pull/569583), which supersedes
  the closed [case-repair PR #542813](https://github.com/NixOS/nixpkgs/pull/542813).
  The guarded Node 24 release backport was later retired when the main Nixpkgs
  pin reached `7fd4004d0511991fff3a0524856a9be09e28c5f0`, whose recipe selects
  the same source, translations and dependency cache. The old case-path rewrite
  is removed; secret-log redaction remains necessary in 26.10.0.
- Claude Code 2.1.285 builds natively on aarch64-darwin with install checks enabled.
  Its temporary fix now changes only `__noChroot`. [Nixpkgs PR #566625](https://github.com/NixOS/nixpkgs/pull/566625)
  remains open.
- Homebridge LG ThinQ moves from 1.0.39 to [1.1.2](https://github.com/mp-consulting/homebridge-lg-thinq/releases/tag/v1.1.2).
  Upstream now locks the repaired brace-expansion dependency, so the local lockfile
  and replacement phase were removed.
- Ghostty's Bash patch still serves 1.3.1, the latest stable release reviewed.
  The merged [PR #11644](https://github.com/ghostty-org/ghostty/pull/11644) does not
  justify removing the backport yet. Its existing version gate and separate
  shell-integration copy now live in the temporary-fix registry with a revision
  guard. This preserves the signed macOS application.

### Retained temporary repairs

| Fix or group | October 4 evidence and decision |
| --- | --- |
| Actual secret-log redaction | 26.10.0 still logs secret values; retain independently of the source update. |
| Sentry report lock and Determinate module adapter | [Crashpad #171](https://github.com/getsentry/crashpad/pull/171) merged, but selected and current Determinate Nix still use Sentry 0.13.5. Retain until that dependency contains the fix. |
| Hyprshell modifiers and workspace schema | [#521](https://github.com/H3rmt/hyprshell/pull/521), [#522](https://github.com/H3rmt/hyprshell/pull/522), and [#525](https://github.com/H3rmt/hyprshell/pull/525) remain open. |
| GtkSourceView Xvfb | [Nixpkgs #566623](https://github.com/NixOS/nixpkgs/pull/566623) remains open; current recipe still lacks the reset repair. |
| Swift wrapper | [Nixpkgs #566624](https://github.com/NixOS/nixpkgs/pull/566624) remains open. |
| NH elevated HOME | [#758](https://github.com/nix-community/nh/pull/758) merged, but latest released NH remains 4.4.2. |
| Nix Output Monitor build plan | [#304](https://github.com/maralorn/nix-output-monitor/pull/304) remains open. |
| PrismLauncher Darwin watcher test | [#6165](https://github.com/PrismLauncher/PrismLauncher/pull/6165) closed without merging; closure supplies no replacement fix. |
| Stylix nvf and Rofi | [#2497](https://github.com/nix-community/stylix/pull/2497), [#2499](https://github.com/nix-community/stylix/pull/2499), and [#2501](https://github.com/nix-community/stylix/pull/2501) remain open; current source still assigns the deprecated options. |
| Hypridle condition retries | Current upstream retry path still omits inhibitor checks. |
| Hyprland portal | Current compiler options retain the unconditional Clang-specific warning flag. |
| Jellyfin caption defaults | Current upstream getter still mutates the shared defaults object. |
| Microsocks credential files | Current upstream still accepts credentials through command arguments. |
| Prowlarr TorrentDownload | Selected and current upstream definitions are identical and lack the apostrophe normalization and music-title separator filters. Retain. |
| Nixos-anywhere SSH checking | Current upstream still initializes SSH with verification disabled. |
| Moonfin caption background | Current upstream sets background color without selecting the background box. |
| Stirling PDF release and EmbedPDF fallback | [Nixpkgs #568090](https://github.com/NixOS/nixpkgs/pull/568090) remains open; the selected PR head already packages 3.0.2. No verified replacement for the fallback repair. |
| Zoom release and Wayland launch | Current Nixpkgs master packages 7.2.1.5760 with `libuuid`; the selected pin does not. The override already selects that version and supplies `libuuid`. A later compiler-output change reduces closure size but is not a runtime repair. Retain the launch repair pending a successful desktop reproduction without `unset DISPLAY`. |
| Deploy-rs and Determinate Darwin tests, Zen wrapper, Stylix Flatpak polarity, Hyprland teardown, Codex child exit | No demonstrated replacement on the selected sources. Preserve the fixes and their focused checks; this review does not claim fresh runtime reproduction for every item. |

Permanent Determinate selection and personal package exposure remain configuration
choices. They do not expire when unrelated upstream issues close.

### Package ownership

Reusable recipes now belong to `nixpkgs-personal`:

| Package | Moved implementation and validation |
| --- | --- |
| `feishin-managed` | Managed-login/player scripts, native macOS titlebar and mpv changes, strict TypeScript compilation and managed-login tests. |
| `jellyfin-web-personal` | Caption controls, rendering patches and appearance defaults. The separate upstream defaults-mutation repair retains its temporary lifecycle. |
| `homelab-iot-scripts` | Homebridge/Scrypted TypeScript helpers and their package checks. Tests requiring a Scrypted server stay in nix-homelab and consume the package's fixtures. |
| `stirling-pdf-engine` | Existing math-intent and privacy-routing patches move from the host into the existing engine recipe. |
| `metabrainz-spicetify-extension` | The standalone TypeScript extension and build move from the Spotify Home Manager module; the module still selects it. |
| `darktable-app-personal` | The reusable macOS app bundle moves from the Darktable Home Manager module. The module still selects a CPU-only Darktable input for this configuration. |

Each new recipe uses dependencies from its caller's Nixpkgs scope and keeps its
sources within its package directory. Module-generated configuration and helpers
with host-specific settings remain with their modules. Evidence patches under
`docs/assets/`, `pkgs/docs/` and test fixtures are not active package overrides.

The nix-seal Cargo workspace keeps its own release build, generated schemas and
module-coupled tests in its source repository. Moving that build downstream would
reverse the documented implementation ownership and risk input cycles. The
framework's documentation, discovery and example activation derivations also stay
with the framework. These are source-project build definitions, not misplaced
configuration package recipes.

Publishing this migration requires the personal-package revision first, then the
nix-homelab input update and root gitlinks. Local homelab validation uses the
reviewed local personal-package input without changing its public input URL.

The broader package contract exposed a pre-existing AudioMuse Navidrome plugin
metadata mismatch: the public Linux output advertised only its internal WASI
target, while the flake bypassed the ordinary platform filter. The public package
now installs the unchanged cross-built archive through a native Linux packaging
stage. The special availability exception is removed. The unchanged independence
contract passes on all three supported package systems; installation checks
verify the archive, WASM header, permission and license.

### Personal package patches

| Package | Decision |
| --- | --- |
| Actual CLI | Retain credential-file support. |
| Aurral | Retain artist identity, canonical artwork, native audio tags, Lidarr metadata and both ListenBrainz integrations. Newer 2.10.0 requires rebasing discovery, connection and identity patches; no equivalent upstream implementation was established. |
| FreshRSS visual | Retain grid compatibility and the selected reader appearance. |
| Homebridge Blueair | Redaction remains applicable even on newer 1.2.2. |
| Homebridge Samsung | Pairing-token redaction retired after [maintainer review](https://github.com/tavicu/homebridge-samsung-tizen/pull/761#issuecomment-6065407879). Upstream diagnostic logging is retained. |
| Homebridge tsvesync, PlayStation | Selected releases remain current; keep credential files and directed discovery. |
| Hyprlock personal | Retain authentication controls; selected source is newer than the latest 0.9.6 release. |
| Noctalia greeter | Retain authentication UX while [#141](https://github.com/noctalia-dev/noctalia-greeter/pull/141), [#142](https://github.com/noctalia-dev/noctalia-greeter/pull/142), [#143](https://github.com/noctalia-dev/noctalia-greeter/pull/143), and [#144](https://github.com/noctalia-dev/noctalia-greeter/pull/144) remain open. |
| Noctalia personal | Retire calendar and workspace IPC fixes in 5.2.1; retain the seven intentional icon, player, color, workspace appearance and wired-uplink changes. [Tray PR #4579](https://github.com/noctalia-dev/noctalia/pull/4579) remains open. |
| ReactFlux | Retain deployment/authentication integration. |
| Soularr | Selected 1.2.2 is current; retain shared-client behavior. |
| Stirling engine | Retain writable state and routing behavior. |
| Vorssaint | [Fan helper #2022](https://github.com/vorssaint/vorssaint-utils/pull/2022) merged after latest stable 3.4.0. That release still requires the patch. The obsolete Swift patch was already removed in the previous update. |
| Wardrowbe | Retain backend Redis/AI/planning and frontend model/OIDC/planning changes. Newer 1.10.3 still needs the backend AI import patch rebased and the combined behavior tested. |

Open packaging PRs for Claude Desktop, Raspberry Pi Imager on Darwin and Steam
on Darwin, plus Stylix font units and systemd-boot counted entries, were reviewed
as related author history. None provides a replacement for the selected patches.

The own-repository history confirms earlier superseded work: package PRs
[#59](https://github.com/nix-forge/nixpkgs-personal/pull/59) and
[#60](https://github.com/nix-forge/nixpkgs-personal/pull/60) closed in favor of
merged [#62](https://github.com/nix-forge/nixpkgs-personal/pull/62). Configuration
PRs #207 through #214 closed because merged
[#215](https://github.com/nix-forge/nix-conf/pull/215) incorporated that stack.
Merged [#133](https://github.com/nix-forge/nix-conf/pull/133) already retired
Oxlint, Darktable and libgphoto2 overrides and the Electron 40 exception. Their
absence is intentional; no current fix should be recreated from those closed PRs.

Inline source changes were also reviewed across 35 package and helper expressions.
The retained groups include font/icon variants, region-only Grimblast, Spotify
SpotX, Feishin and Jellyfin integration, ReactFlux assets/defaults, Soularr
ownership handling, and Noctalia/greeter sources and tests. Offline-build and
store-path adaptations remain necessary for Wardrowbe fonts, T3 dependencies and
Electron cache, Intro Skipper version metadata, PowerShell targets, Maintainerr
state paths, Codex libc detection, Hyprlock dependency separation and Scrypted
native addons. These are package integration choices; a merged PR elsewhere is
not evidence that they can be removed.

Specific inline compatibility repairs also remain: Bibata's pinned source and
current master still use a shared temporary SVG filename; FreshRSS needs content
cache keys because Nix normalizes modification times; Stirling requires Pydantic
AI 1.x and the viewer font repair. AudioMuse's compatible SDK pins and scoped
native dependency test overrides have no replacement build evidence. Aurral's
Node engine declaration needs review with its next source update. Homebridge
tsvesync lockfile additions and Blueair dependency remediation remain explicit
packaging changes. LG ThinQ's replacement lockfile was retired with its update.

### Validation of the follow-up

Native aarch64-darwin builds passed for unmodified Helium 0.18.2.1, sandboxed
Claude Code 2.1.285 with install checks enabled, and the extracted Rust secure-files
package with Cargo and installed-release tests. Actual 26.10.0 also built under
the strict Darwin sandbox with secret redaction and without the former case-path
workaround. Its temporary loopback instance passed version/help, health and
frontend delivery checks. This does not test an existing budget's migration.

The extracted IoT package built on x86_64-linux and passed TypeScript, lint,
formatting and behavior checks. Independent migration review checked callers,
package scope, source/test preservation and metadata. It caught a stale
Jellyfin documentation link and inappropriate inherited variant updaters; both
were corrected. Desktop integration and the remaining package checks are recorded
below when complete. No activation is part of this review.

The final Feishin variant passed a native aarch64-darwin build with strict
TypeScript, lint, formatting and managed-login tests. The complete Darwin
configuration evaluated, and the temporary-fix registry check passed across its
supported-platform matrix. Homebridge LG ThinQ 1.1.2 compiled on the MacBook with
explicit unsupported-platform consent used only for this verification; its
published metadata remains Linux-only. The installed plugin, schema and UI
assets passed their checks. Native Linux validation is still required below.

Noctalia 5.2.1 passed its native x86_64-linux build, bar-icon and route-preference
checks, upstream workspace-backend and icon-resolver tests, and packaged config
validation. Its command also accepted the currently installed desktop configuration.
No live shell, lockscreen or visual interaction was activated for this review.
The registered Ghostty Bash integration built and passed syntax validation on
native aarch64-darwin.

The MetaBrainz extension move preserves its source and TypeScript compiler
settings. Its direct TypeScript compile, generated JavaScript syntax check,
Nix syntax parse, formatting check, native aarch64-darwin package build, and
isolated x86_64-linux package build pass.
The new Darktable app package also builds on aarch64-darwin; its executable link
and `Info.plist` passed inspection. The personal-package repository's `just check`
passed all-system evaluation. With the local personal-package input, desktop
Spicetify evaluated to the new extension derivation, the macOS Home Manager
profile evaluated to the built Darktable app derivation, and the Darwin
temporary-fix check passed. The full desktop closure build is still queued
behind other work and has not validated these latest package moves.

## October 6 overlay selection check

The root Nixpkgs input remains at `c59305bab2065cfecc4944690d9eedbb56f3a9fa`,
the revision reviewed by the temporary-fix registry. Its selected packages
still include Actual 26.9.0, Ghostty 1.3.1, NH 4.4.2, Nix Output Monitor 2.2.0,
Hypridle 0.1.8, Hyprshell 4.10.8, and Stirling PDF 2.14.3. The version-gated
fixes therefore remain applicable. The registry check passed across supported
platforms. The upstream [Stylix nvf](https://github.com/nix-community/stylix/pull/2499),
[Stylix Rofi](https://github.com/nix-community/stylix/pull/2501), and
[Nix Output Monitor](https://github.com/maralorn/nix-output-monitor/pull/304)
repairs remain open. The [Actual release update](https://github.com/NixOS/nixpkgs/pull/569583)
does not change the selected Nixpkgs revision.

Two Linux entries in `overlays/packages.nix` were redundant. The Linux
`claude-code` entry returned the incoming package unchanged. The Linux
`prismlauncher` entry supplied its existing `prismlauncher-unwrapped` input
back to the wrapper. Both selected derivations matched their unmodified Nixpkgs
derivations exactly. Those entries are removed on Linux; their Darwin fixes
remain selected. No other active temporary fix met its recorded removal
condition at this pin. This is an evaluation and source review, not a new
runtime reproduction of every retained patch.
