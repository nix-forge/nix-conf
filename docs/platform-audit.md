# Linux and Darwin platform audit

Reviewed the working tree on 2026-09-06, including `pkgs`, `nix-seal`, and
`nix-config-framework`. The initial search found 235 matching lines across 80 Nix
files. This includes declarations, commented examples, and tests, rather than
235 independent conditions. The inventory below covers every matching file.
The review also covered native paths, service managers, package metadata,
platform-specific module directories, and the host module lists.

The supported targets are `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.
The pinned Nixpkgs rejects `x86_64-darwin`; these changes do not add Intel Mac
support.

## Changes

- Codex Desktop appearance now follows Desktop package availability on both
  platforms. It was accidentally coupled to Apple Reminders support. Reminders
  packages and skills retain their own availability check. Appearance activation
  now respects Home Manager dry runs.
- Actual's server configuration supports a Linux systemd user service alongside
  the Darwin launchd agent. Both use the same package, generated JSON, loopback
  policy, private directories, and launcher. The Linux service prepares state
  before starting and restarts on failure. Setup and optional browser opening
  respect activation dry runs. Actual remains disabled on the configured
  MacBook. This makes the module reusable without starting a new service.
  Actual documents both platforms and the server's `--config` interface in its
  [installation guide](https://actualbudget.org/docs/install/) and
  [server CLI guide](https://actualbudget.org/docs/install/cli-tool/).
- Rootless Docker configuration now follows the daemon capability. Integrated
  NixOS inherits `virtualisation.docker.rootless.enable`. Standalone Linux can
  set `programs.docker-cli.rootless.enable = true` after provisioning a user daemon
  and setting `home.uid`. Other profiles retain the shared Docker tools without
  selecting a nonexistent socket or installing unusable systemctl helpers.
  The desktop retains rootless Docker; the MacBook retains Colima.
- mpv's source-colorspace hint moved into `desktop.hdr`. Enabling Linux alone no
  longer applies a Hyprland HDR setting. MPRIS remains Linux-specific. The
  configured HDR desktop retains the hint and the MacBook does not receive it.
- Nushell's Ctrl-W and Ctrl-U bindings apply to both platforms. Ghostty's macOS
  Option/Delete mappings send those same control sequences. Git now ignores
  `.DS_Store` on both, including copied directories and shared checkouts.
- Font installation no longer depends on enabling Fontconfig in the NixOS or
  Home Manager adapter. Native Darwin applications still need installed fonts
  when Fontconfig is disabled. Scan-time Linux emoji policy remains Linux-only.
- Remindctl and Teams adapters follow package availability. Their private
  packages currently supply Apple Silicon builds, so a generic Darwin check was
  broader than their support. Desktop package exports follow its source map;
  the Spotify dispatcher checks the architecture of its macOS artifact.
- General pre-commit checks now exist on Linux in all four flakes. Darwin-only
  local-control Clippy and Rust tests remain gated. The package repository's C
  and Swift source-format checks run on both; xcrun, native app analysis, and
  macOS runtime suites retain their Darwin guards.
- Spotify autostart suppression and the Linux PROJECTS directory use positive
  Linux predicates instead of treating every non-Darwin platform as Linux.

## Boundaries retained

An OS check belongs around a native mechanism such as launchd, systemd, Apple app
bundles, TCC, Keychain, `/run/user`, Linux portals, or native browser storage. It
is insufficient when the actual requirement is a package architecture, an
enabled daemon, or an HDR compositor.

Typed NixOS and nix-darwin module exports already establish a platform boundary.
Their native options do not need another platform predicate on every definition.
Shared Home Manager modules need native adapters around those definitions.
Assertions are useful for opt-in modules that cannot work on another OS;
silently dropping an explicitly enabled service would hide an error.

Shared browser policies, LibreOffice preferences, shell history and completion,
Ghostty clipboard and palette settings, and common development tools already
apply to both. They were retained. The host lists deliberately differ in desktop
shell, hardware, native applications, and optional workloads. A missing host
import alone does not justify enabling an optional workload. AeroSpace, Fusion,
and TCC belong to the MacBook. Hyprland, portals, AppArmor, and hardware policy
belong to the desktop.

The existing nix-seal runtime split is intentional. Linux service credentials,
volatile mounts, launchd ordering, native runtime groups, and standalone-storage
warnings express different operating-system guarantees. No runtime secret policy
was broadened.

Git's built-in fsmonitor setting remains Darwin-specific, as do Unicode filename
precomposition and Keychain credentials. tmux's `secureSocket` remains Linux-only.
The pinned Home Manager implementation sets `TMUX_TMPDIR` to `XDG_RUNTIME_DIR`
or `/run/user/$(id -u)`; its name does not mean generic socket security.

Pinned Home Manager, nix-darwin, and package sources were the implementation
reference. In particular, pinned nix-darwin allows auto-optimise-store on fixed
Nix versions. Historical advice to disable it on every Mac does not justify
changing the current configuration.

## Validation

The new `checks.<system>.platform-contracts` evaluates all three supported
platforms. It covers enabled and disabled Actual services, native service
selection, standalone and integrated rootless Docker, rejection of Darwin
rootless configuration, portable shell settings, package availability versus
metadata, fonts with Fontconfig disabled, and the real hosts' Desktop appearance
and HDR settings. Darwin and ARM values are evaluated without running foreign
binaries.

- The platform contract builds on `desktop`.
- The complete desktop closure builds on `desktop`, without activation.
- The complete MacBook system derivation evaluates. A native macOS build and
  macOS runtime behavior were not exercised here.
- All-system evaluation succeeds for the package, framework, and nix-seal
  submodules. Their local development input directories first needed adding to
  the Nix store because the evaluator reported missing `*-dev` source paths.
- The root all-system flake check reaches an existing desktop contract mismatch.
  `hasHomePackage "noctalia"` expects the upstream name while the working tree
  selects `noctalia-personal`. This audit does not change that selection.
- The newly enabled Linux pre-commit build executes, exposing existing checkout
  problems, including font Python lint and dependency issues, generated-artifact
  formatting, and a non-executable Hyprland test script. Broad pre-commit is not
  green. Formatting and static checks were applied to this audit's changed Nix
  files separately.

No activation, deployment, commit, lockfile update, or changes to optional-service
enablement were performed. Existing staged and unstaged work was preserved.
Submodule edits remain in their respective working trees.

## Complete predicate inventory

Line numbers refer to the initial search before these edits. Declarations and
their uses are grouped by file.

| File | Initial lines | Decision |
| --- | --- | --- |
| `flake/dev/checks.nix` | 19, 42, 121, 902 | Keep the Fusion/macOS host boundary and native test execution. Portable helper tests remain shared. |
| `flake/dev/git-hooks.nix` | 18 | Changed. Share general checks; retain guards on native compilation and macOS app tools. |
| `flake/dev/shell.nix` | 10, 11, 50 | Keep Darwin libiconv linkage and native Swift analysis tools; common development packages are shared. |
| `homes/macbook-pro-m4/local/dev-vm.nix` | 8, 152 | Keep the Fusion/macOS host boundary and native test execution. Portable helper tests remain shared. |
| `homes/macbook-pro-m4/local/local-control.nix` | 8, 187 | Keep the Fusion/macOS host boundary and native test execution. Portable helper tests remain shared. |
| `homes/macbook-pro-m4/local/local-control/runtime-helpers.nix` | 16 | Keep the Fusion/macOS host boundary and native test execution. Portable helper tests remain shared. |
| `modules/home/actual.nix` | 8, 46, 120 | Changed. Share server options/setup, with systemd on Linux and launchd on Darwin. |
| `modules/home/bitwarden.nix` | 8, 33, 48, 50, 56 | Keep native app/proxy paths, manifest locations, and copyApps/launchd versus XDG startup adapters. |
| `modules/home/browsers/firefox/default.nix` | 17, 50, 64 | Keep signed Darwin app selection and install-registry reconciliation; share profiles and policies. |
| `modules/home/browsers/shared/bitwarden-native-messaging.nix` | 9, 19, 45, 54, 67, 68, 73, 105 | Keep native app/proxy paths, manifest locations, and copyApps/launchd versus XDG startup adapters. |
| `modules/home/browsers/shared/default.nix` | 10, 237, 245 | Keep common policy values with native MIME/LaunchServices and JSON/plist adapters. |
| `modules/home/browsers/shared/profile.nix` | 46 | Keep Gecko Fontconfig preferences Linux-only; native macOS Gecko uses Core Text. |
| `modules/home/browsers/zen/default.nix` | 80 | Keep signed Darwin app selection and install-registry reconciliation; share profiles and policies. |
| `modules/home/browsers/zen/shopping.nix` | 22 | Keep native Application Support versus XDG config-directory selection; settings remain shared. |
| `modules/home/cli/mole.nix` | 2 | Keep native macOS application support, preferences, signing, TCC, and login integration. |
| `modules/home/cli/remindctl.nix` | 9, 12 | Changed. Follow exported package availability rather than a broad Darwin check. |
| `modules/home/darktable.nix` | 3, 34 | Keep only the macOS application wrapper Darwin-specific; the CPU package is shared. |
| `modules/home/desktop/applications.nix` | 9, 49 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/bar.nix` | 9, 26 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/capture.nix` | 9, 57 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/clipboard.nix` | 9, 60 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/core.nix` | 9, 17 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/hdr.nix` | 9, 90 | Changed. Own mpv source hints with opt-in Hyprland HDR support. |
| `modules/home/desktop/idle.nix` | 10, 74 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/launcher.nix` | 9, 17 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/night-light.nix` | 9, 25 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/notifications.nix` | 9, 24 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/optional-emoji-fonts.nix` | 25, 27 | Keep native macOS font installation separate from Linux optional data files. |
| `modules/home/desktop/osd.nix` | 9, 51 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/desktop/wallpaper.nix` | 9, 801 | Keep Linux assertion and desktop capability checks for Wayland/Hyprland tools or systemd user services. |
| `modules/home/dev/agentic-gui/claude-desktop.nix` | 9, 12 | Keep. Pinned private packages only supply Apple Silicon apps. Linux Steam is owned by NixOS elsewhere. |
| `modules/home/dev/agentic-gui/t3-code.nix` | 9, 12 | Keep. Pinned private packages only supply Apple Silicon apps. Linux Steam is owned by NixOS elsewhere. |
| `modules/home/dev/agentic-tui/claude.nix` | 4 | Keep the narrow Darwin sandbox/install-check workaround; install the CLI on both. |
| `modules/home/dev/agentic-tui/codex.nix` | 10, 11 | Changed. Separate Desktop appearance availability from Reminders support. |
| `modules/home/dev/agentic-tui/opencode.nix` | 10, 269, 280, 283 | Keep native notification adapters; share event preferences. |
| `modules/home/dev/containers.nix` | 9, 13, 15, 27, 29, 49, 51, 87, 118, 119 | Changed. Select rootless context and helpers by daemon capability or explicit opt-in; retain Colima on Darwin. |
| `modules/home/dev/git.nix` | 8, 10, 11, 26, 72, 97, 98 | Changed. Share .DS_Store ignore; retain native credentials, fsmonitor, and Unicode handling. |
| `modules/home/discord.nix` | 3, 15, 16 | Keep explicit tray UX differences. Common Vesktop preferences are already shared. |
| `modules/home/helium-browser/default.nix` | 13, 17, 102, 104, 131 | Keep structural selection of distinct upstream adapters via the supplied system argument, avoiding config-dependent imports. |
| `modules/home/helium-browser/flags.nix` | 3, 11 | Keep Linux Ozone/VAAPI flags isolated; startup and download policies are shared. |
| `modules/home/karakeep.nix` | 8, 28, 109, 150, 198, 215 | Keep shared Compose config with systemd versus Colima/launchd adapters. Darwin VM port exposure accompanies an explicit forwarding helper. |
| `modules/home/libreoffice.nix` | 10, 14, 16, 216, 251, 338, 369, 415 | Keep native package/profile locations and systemd/launchd grammar service; document and language settings are shared. |
| `modules/home/linearmouse.nix` | 8, 102 | Keep native macOS application support, preferences, signing, TCC, and login integration. |
| `modules/home/macos/core-packages.nix` | 8, 180 | Keep macOS native command wrappers and priority policy together; do not export invalid native paths to Linux. |
| `modules/home/macos/ocr-capture.nix` | 8, 179, 184, 191, 193, 198 | Keep native macOS application support, preferences, signing, TCC, and login integration. |
| `modules/home/microsoft-teams.nix` | 9, 12 | Changed. Follow exported package availability rather than a broad Darwin check. |
| `modules/home/mpv/default.nix` | 8, 42, 59 | Changed. Move HDR policy to desktop.hdr; retain Linux MPRIS and common playback/shader controls. |
| `modules/home/shells/bash/config.nix` | 3, 13 | Keep Linux VTE integration; shell completion, history, and editing settings remain shared. |
| `modules/home/shells/nushell/config-dir-fix.nix` | 11 | Keep native Application Support versus XDG config-directory selection; settings remain shared. |
| `modules/home/shells/nushell/settings.nix` | 8, 82 | Changed. Share Ctrl-W/Ctrl-U terminal control sequences. |
| `modules/home/shells/tmux.nix` | 9, 173 | Keep. secureSocket uses XDG_RUNTIME_DIR or /run/user; it is a Linux runtime-directory policy. |
| `modules/home/shells/zsh/config.nix` | 3, 10 | Keep Linux VTE integration; shell completion, history, and editing settings remain shared. |
| `modules/home/spotify.nix` | 11, 23, 28, 116, 134, 144 | Clarified Linux autostart predicate. Keep native preference paths, pgrep, bundle registration, and launchd cleanup. |
| `modules/home/steam-darwin.nix` | 9, 12 | Keep. Pinned private packages only supply Apple Silicon apps. Linux Steam is owned by NixOS elsewhere. |
| `modules/home/terminals/ghostty/default.nix` | 8, 42, 83, 114 | Keep native bundle, GTK, cgroup, secure-input, and window conventions; share fonts, palette, clipboard, and shell settings. |
| `modules/home/vscode/keybinds.nix` | 3, 9 | Keep native Command/Control and terminal-profile key selection; editor behavior remains shared. |
| `modules/home/vscode/languages/cpp.nix` | 28, 33, 34 | Commented examples only; no active platform behavior. |
| `modules/home/vscode/settings.nix` | 179 | Keep native Command/Control and terminal-profile key selection; editor behavior remains shared. |
| `modules/home/whatsapp.nix` | 3, 6 | Keep native macOS application support, preferences, signing, TCC, and login integration. |
| `modules/home/xdg/default.nix` | 8, 28, 32, 39, 40 | Clarified Linux PROJECTS predicate. Retain native Movies/Templates and Developer conventions; share base paths and screenshots. |
| `modules/home/xdg/portal.nix` | 10, 25, 38 | Keep Linux portal integration and OS ownership detection; macOS has no equivalent XDG service. |
| `modules/nixos/virtualisation/libvirt.nix` | 656 | Keep defensive Linux assertion for the NixOS libvirt implementation. |
| `modules/shared/chromium-policies.nix` | 201, 460, 461 | Keep common policy values with native MIME/LaunchServices and JSON/plist adapters. |
| `modules/shared/determinate.nix` | 90, 95 | Keep Apple Silicon support assertion and native daemon/build workarounds. |
| `modules/shared/fonts.nix` | 162 | Changed. Decouple font packages from Fontconfig enablement; retain Linux emoji scan policy. |
| `modules/shared/stylix/default.nix` | 257, 284 | Keep Linux cursors/icons separate. Share palette/fonts and Fontconfig settings for applications that use that backend. |
| `nix-config-framework/flake/dev/git-hooks.nix` | 6 | Changed. Share general checks; retain guards on native compilation and macOS app tools. |
| `nix-seal/flake/dev/git-hooks.nix` | 21 | Changed. Share general checks; retain guards on native compilation and macOS app tools. |
| `nix-seal/flake/dev/shell.nix` | 15, 16, 58 | Keep Darwin libiconv linkage and native Swift analysis tools; common development packages are shared. |
| `nix-seal/flake/production.nix` | 16, 107 | Keep Darwin linkage and architecture-specific NixOS VM check; package support already includes both OS families. |
| `nix-seal/nix/modules/home-manager.nix` | 12, 17, 49, 57, 76, 101, 114, 116, 144, 174, 178, 201, 222, 227 | Keep native runtime ownership, systemd credentials, launchd ordering, storage warnings, and their tests. |
| `nix-seal/nix/modules/shared.nix` | 595, 743 | Keep native runtime group defaults: staff on Darwin, user group on Linux. |
| `nix-seal/nix/tests/module-evaluation.nix` | 175, 307, 314, 321 | Keep native runtime ownership, systemd credentials, launchd ordering, storage warnings, and their tests. |
| `pkgs/flake/dev/codex-desktop.nix` | 25, 26, 33 | Keep native verification tools and Mach-O versus ELF checks; share Python updater tests. |
| `pkgs/flake/dev/git-hooks.nix` | 6, 59, 68, 78, 92, 102, 112, 121 | Changed. Share general checks; retain guards on native compilation and macOS app tools. |
| `pkgs/flake/dev/icon-themes.nix` | 10 | Keep builds of Linux desktop packages Linux-only. |
| `pkgs/flake/dev/shell.nix` | 11, 12, 51, 60 | Keep Darwin libiconv linkage and native Swift analysis tools; common development packages are shared. |
| `pkgs/pkgs/by-name/op/openai-codex-desktop/package.nix` | 56, 79 | Keep separate signed ZIP bundle and patched Linux DEB builds; source selection rejects unavailable artifacts. |
| `pkgs/pkgs/by-name/sp/spotify-spotx/package.nix` | 33, 35 | Changed. Require Apple Silicon for the Darwin adapter, matching the source and metadata. |
| `pkgs/pkgs/default.nix` | 49, 55, 58, 59, 61, 63 | Changed. Desktop exports follow the source map; retain native desktop and architecture-specific package sets. |
