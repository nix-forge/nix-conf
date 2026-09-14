# Technology choices for the workstation configuration

Reviewed: 2026-09-10. Scope: the current root working tree and its three
submodules, including existing uncommitted work. Root base:
`7fd38c80a2aabdb16674fba7231496fa4a575bee`.

## Answer

Keep the Nix foundation, nix-seal, and the current desktop architecture. The
project already uses recent approaches across system configuration, desktop
composition, Python tooling, and automated checks. A broad framework rewrite
would incur substantial migration work without an established benefit.

The strongest improvements are completing recovery and boot protection,
reducing the maintenance cost of patches, and making editor and CI tooling
agree. The repository website should launch on the existing reproducible MkDocs
build, then use a bounded Zensical migration trial to decide its longer-term
engine. There are also worthwhile small experiments with a different VS Code
extension catalog and Swift Testing. These are candidates to validate, not
proven replacements.

Retaining nix-seal is a settled project requirement. Its improvement path is
release assurance and recovery testing within that implementation.

Recommendations below are engineering judgments based on inspected configuration
and primary sources. "Current" means suitable and maintained for the observed
requirements. It does not mean every package is the newest upstream release.

## What was reviewed

This is a technology and architecture review, not an exhaustive audit of every
transitive package, application feature, extension, or vulnerability. The
inventory covers direct flake inputs, selected host and home modules, local
programs, tests, packaging, CI, and the documentation build. Ordinary desktop
applications are grouped by role. Package recipes do not prove installation;
selected modules do not prove runtime activation.

The main local evidence is the [root flake](../flake.nix),
[Linux home](../homes/desktop/default.nix),
[macOS home](../homes/macbook-pro-m4/default.nix),
[Linux host](../hosts/nixos/desktop/default.nix),
[macOS host](../hosts/darwin/macbook-pro-m4/default.nix), and
[package catalog](../pkgs/docs/catalog.md).

### Direct input inventory

All 26 direct root inputs are accounted for here. Development-only inputs are
listed separately. Entries grouped together have related roles, not necessarily
the same update schedule.

| Inputs | Role and recommendation |
| --- | --- |
| `nixpkgs`, `nix-darwin`, `home-manager` | System and user configuration. Keep the current NixOS unstable workstation track and coherent upstream modules. |
| `determinate` | Selected Nix implementation. Keep while measuring its benefit and maintenance cost. |
| `flake-parts`, `nix-config-framework` | Flake composition and project-specific target/module discovery. Keep and improve portable examples. |
| `nix-seal` | Secret authoring, signed deployment artifacts, and runtime activation. Keep; prioritize assurance. |
| `nixpkgs-personal` | Independent recipes, native helpers, fonts, and patched application variants. Keep repository ownership separate. |
| `deploy-rs` | Remote NixOS deployment. Keep pending a demonstrated operational limitation; local Darwin recipes use `nh darwin`. |
| `hyprland`, `hyprlock`, `noctalia` | Linux compositor, lock screen, and desktop shell. Keep the current integration. |
| `stylix`, `spicetify-nix` | Shared appearance and Spotify customization. Keep; reduce local patches when upstream catches up. |
| `nvf`, `nix4vscode` | Neovim configuration and VS Code extension packaging. Keep nvf; assess the catalog support tradeoff below. |
| `firefox-addons`, `zen-browser` | Gecko extensions and Zen packaging. Keep with browser-engine update tracking. |
| `helium-browser`, `helium-browser-darwin` | Separate platform packaging for Helium. Track platform lag independently. |
| `disko`, `lanzaboote` | Declarative disk provisioning and Secure Boot support. Preserve the tools; distinguish available modules from enabled protection. |
| `stevenblack-hosts` | Pinned DNS blocking data. Keep explicit review of list updates. |
| `systems`, `flake-compat`, `flake-schemas` | Platform inventory, compatibility, and output introspection. No replacement justified by age alone. |

The [development partition](../flake/dev/flake.nix) adds `git-hooks-nix` and
`treefmt-nix`, with its own Nixpkgs, Home Manager, and flake-compat inputs.
The [starter](../templates/starter/flake.nix) deliberately uses the 26.05 release
tracks. Its different track is appropriate for an introductory example.

Observed locked source dates, read from the lockfiles rather than inferred from
release names:

| Input | Locked revision prefix | Source date |
| --- | --- | --- |
| Root and development Nixpkgs | `c043004d1c69` | 2026-09-05 |
| Home Manager | `2c0350c75968` | 2026-09-05 |
| nix-darwin | `4cff07de74b5` | 2026-08-16 |
| flake-parts | `31729ca8cbdb` | 2026-09-03 |
| Determinate | `cb76ac22754f` | 2026-09-03 |
| Hyprland | `34eb03bd8da0` | 2026-09-06 |
| Noctalia flake input | `224da6dd4360` | 2026-09-06 |
| Stylix | `5e3809851f48` | 2026-08-26 |
| disko | `ff8702b4de27` | 2026-06-11 |
| Lanzaboote, explicit `v1.1.0` tag | `7c9a54a7f87b` | 2026-06-22 |

A source timestamp is not the date the lock was updated, proof of the newest
release, or proof that a runtime uses it. Older dates for small compatibility
inputs do not by themselves indicate abandonment. `home.stateVersion` and
`system.stateVersion` are compatibility settings; do not raise them as routine
package upgrades.

### Other technology families

| Area | Observed technologies | Assessment |
| --- | --- | --- |
| Desktop session | Wayland, Hyprland, native Noctalia v5, greetd, hyprlock, hypridle, portals, XWayland, GTK/Qt applications | Already current. Test hardware-dependent behavior before changing components. |
| Audio and hardware | PipeWire, WirePlumber, BlueZ, RTKit, upstream Linux kernel selected by host override, NVIDIA/CUDA integration, zram, systemd memory controls | Keep the current kernel and audio baseline. Benchmark changes against representative workloads. |
| Platform integration | AeroSpace, LinearMouse, native Swift OCR and Finder helpers, macOS launch agents | Keep native platform integration. Improve Swift checks incrementally. |
| Storage and trust | Btrfs, LUKS support, disko, Restic, systemd-boot/Lanzaboote support, TPM2, AppArmor, USBGuard, ClamAV, YubiKey, GNOME Keyring | Tool choice is largely settled; verify which protections are enabled. |
| Networking | NetworkManager, systemd-resolved, Unbound, WireGuard, blocking lists, fail2ban, firewall and tarpit rules | Prefer clear ownership and measured behavior to adding another networking framework. |
| Virtualization | QEMU/KVM, libvirt, Virt Manager, Windows guest provisioning, rootless Docker, Compose, Buildx, Colima/Lima | Keep the existing division between full guests and containers. |
| Container tools | Cosign, Syft, Trivy, Skopeo, Dive, Hadolint | Already available. Installation alone is not evidence of signed images or enforced scanning. |
| Shell and navigation | Bash/ble.sh, Nushell, Zsh, Starship, Atuin, Carapace, fzf, zoxide, eza, ripgrep, tmux, Ghostty | Keep Bash for the established login/SSH path; optional shells serve different workflows. |
| Source control | Git, Jujutsu, gh, glab, privacy hooks | Keep interoperability and existing privacy checks. No replacement justified. |
| Development environments | Nix dev shells, direnv/nix-direnv, just, uv, Node.js/Bun | Use project-local dependency ownership; do not layer another environment manager over every task. |
| Languages and editors | Nix/nixd/nixfmt, Python/Ruff/ty, Rust 2024/Cargo/Clippy, Swift/C bridge, C/C++/Clang, shell, JS/TS, Lua, Typst | Modern choices. Align tools and improve tests at each repository boundary. |
| AI clients | Codex, Claude Code, OpenCode, Cursor; desktop clients and shared skills | Multiple configured clients, not one application framework. Compare completed work and repair time before changing defaults. |
| Desktop applications | Firefox/Zen, Helium/Chrome, Bitwarden, LibreOffice, mpv, darktable, Spotify/Spicetify, Signal, Discord, Zoom, Teams, Notion | Keep according to required workflows. No blanket claim that a newer application is better. |
| Gaming and remote display | Steam, Proton-related integration, PrismLauncher, Moonlight | Keep hardware/game compatibility as the acceptance criterion. |
| Fonts and graphics | Fontconfig, HarfBuzz, Pango, Core Text, Inter, Literata, Monaspace, Noto, optional Apple/Microsoft/legacy emoji collections | Current defaults coexist with intentionally historical artwork. Do not treat old optional fonts as obsolete frameworks. |
| Optional services | Actual Budget and Karakeep modules | Explicitly disabled in the inspected macOS home. Do not treat them as running infrastructure. |
| Tests and quality | pytest/pytest-timeout, Nix checks, NixOS VM tests, Selenium, direct browser protocol scripts, Rust/Swift tests, formatters and scanners | Improve missing behavior coverage rather than replace all test runners. |
| CI and docs | GitHub Actions, shared `nix-forge/ci` workflows, Dependabot, native platform matrix, MkDocs/Pygments, Pages | Already substantial. Preserve reproducible builds and review gates. |

The package repository also owns application wrappers, icon/cursor variants,
font recipes, skill collections, and command-line helpers such as `remindctl`
and PSScriptAnalyzer. Its [catalog](../pkgs/docs/catalog.md) supplies the
package-level inventory and upstream links without duplicating them here.

## Improvements to prioritize

### Preserve the Nix foundation and simplify only proven friction

Keep NixOS, nix-darwin, Home Manager, Determinate, and flake-parts. The selected
unstable tracks are coherent with nix-darwin's upstream guidance. Determinate's
lazy trees and parallel evaluation are already configured; its performance
claims need local measurement before treating a different implementation as
an improvement. [nix-darwin](https://github.com/nix-darwin/nix-darwin),
[Determinate guidance](https://docs.determinate.systems/determinate-nix/best-practices/),
[flake-parts partitions](https://flake.parts/options/flake-parts-partitions.html).

Keep the custom framework. Its [documented contracts](../nix-config-framework/README.md)
include selectors, target discovery, embedded users, shared platform modules,
and the inventory used by nix-seal. An import library cannot replace all of that.

| Candidate | Potential benefit | Decision for this repository |
| --- | --- | --- |
| Plain imports with flake-parts | Fewer discovery conventions | Good for the starter; replacing existing host and secret inventory contracts is not justified. |
| Dendritic pattern | Organizes platform modules around features | Borrow ideas where a feature is hard to follow. It is a module organization pattern, not a successor to NixOS or Home Manager. |
| import-tree | Recursive imports with filtering | Possible internal simplification, but preserve default-module boundaries, exclusions, collisions, and selector behavior. |
| Denix or Snowfall Lib | Ready-made configuration conventions | No missing capability identified that repays changing target and module APIs. |
| Lix | Different implementation and governance tradeoffs | Watch, but first test the Determinate-specific settings and evaluation behavior the project uses. |
| Colmena | Deployment selection and parallel fleet operations | Reconsider if the project grows into a fleet. Keep deploy-rs for the current remote workstation. |
| devenv | Structured development environments and service processes | Useful for a future service-heavy application project; current Nix shells and direnv already cover this repository's checks. |

Sources for those capabilities are the [Dendritic project](https://github.com/mightyiam/dendritic),
[import-tree](https://github.com/denful/import-tree),
[Denix](https://github.com/yunfachi/denix),
[Snowfall guide](https://snowfall.org/guides/lib/quickstart/),
[Lix comparison](https://lix.systems/about/#technical-differences-from-cppnix),
[Colmena manual](https://colmena.cli.rs/unstable/), and
[devenv guide](https://devenv.sh/basics/). The fit decisions are this review's
judgment, not comparative benchmark results.

One small cleanup is worth investigating. The
[shared Nix settings](../modules/shared/nix-settings.nix) enable several
experimental facilities globally, including recursive Nix, impure derivations,
content-addressed derivations, and configurable impure environments. Trace their
consumers, including upstream inputs, and remove only flags that representative
evaluations and native checks establish are unnecessary. A search finding no
direct consumer is insufficient. [Nix experimental features](https://nix.dev/manual/nix/2.35/development/experimental-features).

Keep the existing build queue and memory budgets. Measure wall time, peak memory,
and desktop responsiveness before changing evaluator concurrency. Also retain
deploy-rs rollback and test failed activation and lost confirmation on disposable
targets. Its connectivity rollback does not establish application health.
[Local memory policy](desktop-memory-management.md),
[deployment configuration](../flake/deploy.nix),
[deploy-rs rollback](https://github.com/serokell/deploy-rs#magic-rollback).

### Keep nix-seal and complete its assurance work

The [manifest](../nix-seal/Cargo.toml) declares `0.1.0-alpha.1`. The
[README](../nix-seal/README.md), [specification](../nix-seal/SPEC.md), and
[release guide](../nix-seal/docs/release.md) explicitly distinguish existing
implementation from the independent audit and other gates required for 1.0.
They explicitly state that nix-seal is not yet ready for production secrets.
This is a readiness gap, not evidence of a discovered vulnerability.

Keep the Rust implementation, age-based encryption, signed policy/artifact
contracts, and platform runtime controls. Work through the existing
[recovery runbooks](../nix-seal/docs/runbooks.md) with disposable credentials
on Linux and macOS. Cover cache loss, signer rotation, policy rejection,
interrupted activation, and recovery using the designated recovery identity.
Record the revision and observed result of each exercise.

The repository already has Cargo audit/deny/vet, fuzzing, Miri, sanitizer and
mutation workflows. Adding their names to a checklist would not improve
assurance. Review surviving mutants and narrow accepted dependency exceptions;
commission the independent review required by the project's own release
criteria. Keep public readiness claims consistent with the evidence.

### Finish storage protection using the existing tools

The host explicitly leaves encrypted-root support and Secure Boot disabled,
and Restic destinations remain empty. These are configuration observations,
not a probe of current disks or firmware. See the
[storage selection](../hosts/nixos/desktop/local/storage-deployment.nix),
[boot selection](../hosts/nixos/desktop/local/security-secure-boot.nix),
[storage options](../hosts/nixos/desktop/local/storage/default.nix),
[backup options](../hosts/nixos/desktop/local/storage/backups.nix), and
[Secure Boot module](../modules/nixos/boot/secure-boot.nix).

Use the existing [storage migration guide](disko-desktop-migration.md) and
[storage operations guide](desktop-storage-operations.md) to finish this work.
First establish and test independent backups, then rehearse the intended disk
layout and boot recovery. The existing Restic jobs depend on the future encrypted
layout and its mount points. Adding destinations alone while that layout is
disabled will not back up the current installation. A backup of the current
layout must precede destructive provisioning. Restic's data check is useful but
does not replace a successful restore.
[Restic verification](https://restic.readthedocs.io/en/stable/045_working_with_repos.html).

Disk provisioning and firmware enrollment need their
own operational task. This review does not authorize or perform them.

A change of filesystem, backup framework, or boot manager would not fill the
missing destinations or establish a successful restore. Acceptance should be a
verified restore, boot after an update, and successful recovery after the tested
failure scenarios.

### Keep the desktop and virtualization stack, with narrow trials

The selected Noctalia v5 package is native Wayland/OpenGL ES software. It is not
the older Quickshell implementation. The current configuration also already
uses Hyprland Lua, AeroSpace configuration version 2, and Colima's VZ backend
with virtiofs and Rosetta. These are completed configuration choices, not missing
upgrades. [Noctalia upstream](https://github.com/noctalia-dev/noctalia),
[AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide#config-version),
[Colima](https://github.com/abiosoft/colima).

Keep Hyprland, Noctalia, Stylix, AeroSpace, Ghostty, and the established Bash
login-shell contract. Noctalia's application templates are disabled so Stylix
and Nix retain ownership. A replacement shell would need to reproduce that
division, plus portals, lock/idle handling, and application launching. Compare
runtime results after updates, including monitor hotplug, HDR, screen sharing,
audio restart, tray behavior, suspend, and window switching.
[Stylix module interfaces](https://nix-community.github.io/stylix/modules.html),
[Ghostty integration](https://ghostty.org/docs/features/shell-integration).

| Candidate | When it could improve this project | Cost and acceptance |
| --- | --- | --- |
| Hyprland scrolling layout | Want to try horizontal window organization | Try the built-in layout first; retain existing portal and desktop integration. |
| niri | Prefer its scrolling and per-monitor workspace model | Separate session trial; verify X11 applications, portals, gaming, color behavior, and remote display. |
| KDE Plasma | Want to reduce the amount of custom desktop integration | Compare which local modules and patches can actually be deleted, plus changed keyboard workflows. |
| DankMaterialShell | Need a specific capability absent from Noctalia | Another complete shell with different implementation and integration; no broad migration justified. |
| Podman Quadlet | Add persistent Linux container services owned by systemd | Pilot one service with volume, networking, restart, and backup checks. Keep on-demand Docker development workflows. |
| Apple container | Want to evaluate per-container VM isolation on Apple silicon | Verify host requirements, mounts, architecture, networking, and multi-service compatibility before changing Colima. |

Primary sources describe the [Hyprland scrolling layout](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/),
[niri](https://github.com/niri-wm/niri),
[Plasma](https://kde.org/plasma-desktop/),
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell),
[Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html), and
[Apple container](https://github.com/apple/container). None was benchmarked here.

Keep libvirt/QEMU/KVM and rootless Docker. Rootless Docker is already configured;
it is not a missing security improvement. Complete the existing Windows guest
lifecycle and test restoration of its disk, domain definition, NVRAM, and TPM
state together before adopting another manager.
[Docker rootless design](https://docs.docker.com/engine/security/rootless/),
[libvirt domain model](https://libvirt.org/formatdomain.html),
[existing virtualization review](workstation-virtualization-review-research.md).

Two source details matter when judging newer alternatives. The shared kernel
module declares XanMod, but the [host override](../hosts/nixos/desktop/local/hardware/platform.nix)
selects upstream `linuxPackages_latest` and records a hardware failure that
motivated the change. Keep that baseline until capture reliability is verified.
Similarly, keep GNOME Keyring/GCR; oo7 would require validating more than the
Secret Service API, including login unlock, browser integration, SSH agent, and
PKCS#11 behavior. [XanMod scope](https://xanmod.org/),
[oo7 components](https://github.com/linux-credentials/oo7),
[local keyring contract](../modules/nixos/security/keyring.nix).

### Reduce patch and update maintenance

The [override registry](../overlays/README.md) already requires a reason,
reviewed revision, removal condition, and guards. Keep that mechanism. Use each
input update to test whether its affected upstream package works without the
patch. Retire the whole workaround when the reproduction passes. Do not simply
refresh every guard to make the update evaluate.

Track the workarounds that repeatedly block updates, especially compositor,
portal, desktop shell, browser wrappers, and Nix implementation repairs. Use
that measured burden to choose release tags, upstream packages, or alternative
components. Count review time and recurring failures; the number of newer
frameworks installed is not a useful success metric.

The [Dependabot configuration](../.github/dependabot.yml) already covers Nix,
Git submodules, and GitHub Actions. GitHub now documents Nix support, so migrating
to Renovate merely to obtain flake updates is unnecessary.
[GitHub ecosystem support](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories).

One concrete coverage gap is the new starter lockfile. The root Nix updater lists
`/` and `/flake/dev`, but not `/templates/starter`. Add that directory to the
appropriate update policy and retain its deliberate stable release track.
The existing native starter checks should validate its update. Treat this as a
small follow-up configuration change.

### Align JavaScript tools between editor and checks

The [language module](../modules/home/dev/languages/js.nix) installs Oxlint and
Oxfmt. The [JavaScript editor module](../modules/home/vscode/languages/javascript.nix)
and [TypeScript editor module](../modules/home/vscode/languages/typescript.nix)
still select ESLint/Prettier; the repository's [formatter](../flake/dev/formatter.nix)
uses Prettier too. This is a distinction between available tools and the tools
actually enforcing repository style.

Pilot Oxlint as an explicit check for the repository's maintained JS/MJS files,
then enable the matching editor integration for that scope. Audit rule and file
type coverage first. Keep Prettier as formatter until an Oxfmt comparison passes
on all affected formats and proves useful. Oxc currently labels Oxfmt beta and
publishes compatibility limits; framework script support does not imply template
linting. [Oxc](https://oxc.rs/),
[compatibility matrix](https://oxc.rs/compatibility),
[editor integration](https://oxc.rs/docs/guide/usage/linter/editors.html).

Acceptance is agreement between editor and CI, retained relevant diagnostics,
and no accidental formatting churn. The presence of Node.js or Bun does not
justify adding React, Next.js, Vite, or another application framework to a Nix
configuration repository.

### Keep the Python stack, with deliberate beta adoption

Ruff and ty already own root CI quality checks. The VS Code Python configuration
already selects ty and disables the other Python language server. Installed
mypy/Pyright/Pylance therefore do not establish duplicate running diagnostics.
The current arrangement matches Astral's documented integration.
[Local configuration](../modules/home/vscode/languages/python.nix),
[ty editor guidance](https://docs.astral.sh/ty/editors/).

Keep ty, but recognize that its upstream README still labels it beta and allows
breaking diagnostic changes between versions. Retain pinned updates, review
changed diagnostics, and use the available Pyright or mypy tools to investigate
specific uncertain cases. Do not assume speed claims establish equivalent bug
coverage. [ty status and version policy](https://github.com/astral-sh/ty).

Use uv for Python projects needing their own dependency lock. Continue using
Nix-provided Python dependencies for the existing hermetic repository checks.
Those are distinct responsibilities. [uv project and environment capabilities](https://docs.astral.sh/uv/).

### Improve test coverage without another wholesale migration

The pytest migration is already present in the inspected working tree. Keep
pytest with retained unittest cases, Nix contracts for pure configuration, and
NixOS VM tests for service and boot behavior. Pytest supports this incremental
approach. [pytest compatibility](https://docs.pytest.org/en/stable/how-to/unittest.html),
[NixOS integration testing](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html).

For future tests, Hypothesis is a useful targeted addition for escaping,
configuration round trips, and preservation of unrelated values. Choose one
invariant with generated inputs and keep explicit regression examples. There is
no need to rewrite straightforward subprocess tests.
[Hypothesis documentation](https://hypothesis.readthedocs.io/en/latest/).

Keep Selenium for checks against the actual packaged Firefox/Zen binaries.
Playwright requires matching browser versions and its Firefox support uses a
patched browser. Replacing these checks with Playwright's browser would change
what they prove. Playwright remains a candidate for guide navigation, search,
and ordinary web UI checks.
[Playwright browser requirements](https://playwright.dev/docs/browsers).

The native Swift helpers still use XCTest. Pilot Swift Testing for new pure
logic or parameterized cases when the supported toolchain permits it. Apple
supports running it alongside XCTest. Preserve existing native integration
tests, isolate mutable shared state, and validate both debug and release builds.
Changing test syntax alone has little value.
[Apple Swift Testing](https://developer.apple.com/xcode/swift-testing/).

### Compare the VS Code extension catalogs

Keep VS Code and nvf. The potential improvement is narrower: extension supply
and support. The current nix4vscode README states that public collection of
requirements and issues has stopped. It still documents version-aware extension
selection. That is a support-policy tradeoff, not proof the project is abandoned.
[nix4vscode](https://github.com/nix-community/nix4vscode).

Compare the selected extension set against `nix-vscode-extensions`, which provides
Marketplace/Open VSX snapshots and documents daily updates. Pilot one profile
and measure evaluation time, extension availability, native binary compatibility,
and the ability to retain a known-good version. Keep nix4vscode if its
version-selection capability better meets the project's needs.
[nix-vscode-extensions](https://github.com/nix-community/nix-vscode-extensions).

### Launch and improve the repository website

The website setup is a strong initial implementation. It stages only reviewed
guide content and assets, verifies embedded examples against the public starter,
builds with the pinned Nixpkgs Python environment, enables local search, and uses
strict navigation and link validation. The pinned MkDocs 1.6.1 package matches
the latest stable upstream release on the review date. The documentation
derivation is part of both the required portable lint checks and the ordinary
multi-platform `ciChecks`. The Pages workflow materializes the Nix store output
before upload and limits deployment permissions to `pages: write` and
`id-token: write`. These choices preserve the repository's reproducibility and
publication boundaries. [MkDocs releases](https://github.com/mkdocs/mkdocs/releases).

The planned address, `https://nix-forge.github.io/nix-conf/`, is not live yet.
The public repository reported Pages disabled and an empty homepage field during
this review; the new workflow has not run on GitHub. Enable GitHub Actions as the
Pages publishing source before expecting the workflow to deploy. Add the pinned
`actions/configure-pages` step to the build job, publish once from `main`, verify
the `github-pages` environment and canonical links, then set the repository
homepage to the successful deployment URL. GitHub documents both the initial
enablement requirement and the existing workflow's build/deploy permission
model. [Custom Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

Make the URL policy explicit before the first indexed release. The current
`use_directory_urls: false` produces paths such as `guide/start-here.html`.
MkDocs defaults to directory URLs and describes them as the usual choice. Use
directory URLs for the public site unless opening generated HTML directly from
the filesystem is a product requirement; local review already uses an HTTP
server. Changing this after launch creates a permanent URL migration.
[MkDocs configuration](https://www.mkdocs.org/user-guide/configuration/#use_directory_urls).

Fix the sitemap before launch. Every generated entry currently reports
`1980-01-01` as its last-modified date because the reproducible Nix source
timestamp becomes the page update time consumed by MkDocs's stock sitemap.
Those dates are deterministic but false. Override the sitemap to omit `lastmod`,
or derive truthful dates from reviewed source history without making the build
impure. Add an output assertion that rejects the build epoch.
[MkDocs sitemap template](https://github.com/mkdocs/mkdocs/blob/1.6.1/mkdocs/templates/sitemap.xml).

Correct the page-level source action at the same time. `edit_uri` uses a
read-only `blob/main/docs/` URL, while the stock theme labels it “Edit on GitHub.”
Either change the path to `edit/main/docs/` so the action matches its label, or
override the label to “View source.” The guide invites contributions, so the
actual edit path is the better fit.

The built site already has canonical links, a sitemap, a useful local search,
responsive navigation, descriptive image alternatives, visible focus styling,
and no third-party analytics. Its generated HTML does not contain a description
meta tag despite the configured `site_description`, and it has no Open Graph or
Twitter metadata. It also ships the generic MkDocs favicon, while the home page
title is the vague `Overview - nix-conf`. Add a small theme override that gives
the home page a descriptive title, emits description and social preview tags,
and uses a stable project favicon. Google recommends descriptive page titles and
a crawlable, representative favicon. [Title links](https://developers.google.com/search/docs/appearance/title-link),
[favicon guidance](https://developers.google.com/search/docs/appearance/favicon-in-search).

Treat accessibility and external-link checks as release checks rather than
theme claims. Add a skip link and semantic navigation/main landmarks if the
chosen theme does not render them, then test the landing page, nested guide page,
search, theme switcher, table overflow, and mobile navigation with keyboard-only
use and an automated accessibility checker. W3C recommends semantic page regions,
logical headings, and ways to bypass repeated blocks.
[Page structure](https://www.w3.org/WAI/tutorials/page-structure/),
[WCAG 2.2](https://www.w3.org/TR/WCAG22/). Keep MkDocs strict validation for
internal pages and anchors, and add a separate built-site link check for external
URLs; MkDocs does not verify whether remote destinations respond.

The generated artifact is about 2.3 MiB, including about 1.1 MiB of source maps
and font formats. That is an artifact-size observation, not a transfer benchmark.
Measure a deployed page before removing assets. If the browser does not use
those files, omit unnecessary source maps and redundant font formats from the
published artifact. A custom web application framework is not needed for this
work.

### Compare Zensical with the existing MkDocs guide

The new guide uses stock MkDocs, Pygments, a small custom stylesheet, and a Nix
build. That is a reasonable launch baseline. Zensical is the most relevant newer
candidate to test because it reads `mkdocs.yml` and documents gradual migration.
Zensical still identifies itself as alpha software, and its strongest stated
compatibility target is Material for MkDocs. This project uses the stock MkDocs
theme, so compatibility is not a drop-in guarantee. A local trial with the
currently pinned Zensical 0.0.59 rejected the stock `mkdocs` theme because
Zensical provides its own modern and classic themes. It also requires the
documentation and output directories to remain within its project root. The
current build deliberately stages documentation in a temporary directory and
writes to a caller-selected output, so both contracts need adaptation.
[Zensical roadmap](https://zensical.org/about/roadmap/),
[migration guide](https://zensical.org/docs/compatibility/mkdocs/migration/),
[basic setup](https://zensical.org/docs/setup/basics/).

This repository calls MkDocs's Python API directly in
[site/build.py](../site/build.py). Switching the executable name alone will not
replace that integration. A pilot must adapt the build while preserving reviewed
content staging and source-snippet verification. Compare mobile navigation,
search, keyboard use, deep links, metadata, custom CSS, and offline behavior
before deciding. First make it build reproducibly from the pinned Nix input, then
compare the rendered result. Keep MkDocs for the initial Pages launch so the
engine migration does not hide deployment or content defects.

Astro/Starlight is another credible documentation option, especially if the site
later needs interactive components. Here it would add a frontend dependency
pipeline and content migration. There is no observed requirement justifying that
cost today. [Starlight](https://starlight.astro.build/).

## Suggested order of work

These are proposed follow-up tasks. Effort is relative and does not include
waiting for an external audit or acquiring backup storage.

| Order | Work | Effort | Evidence needed to accept it |
| --- | --- | --- | --- |
| 1 | Keep nix-seal and close its release-assurance gaps | High | Revision-specific independent review, remediations, and native recovery results. |
| 2 | Back up the current storage layout and rehearse recovery | Medium to high | Independent restored data before any destructive migration. |
| 3 | Complete the already-designed encryption and boot-protection rollout | High | Recovery media, verified boot/rollback, and post-migration restore checks. |
| 4 | Cover the starter lockfile in update policy; retire obsolete workarounds | Low per change | Starter checks and each patch's original regression check. |
| 5 | Align JS linting and trace experimental Nix flags | Low to medium | Editor/CI agreement and representative native checks. |
| 6 | Launch the existing site and close its URL, sitemap, metadata, accessibility, and link-check gaps | Low to medium | Successful Pages deployment, truthful sitemap, correct canonical/source links, and keyboard/mobile checks. |
| 7 | Trial Zensical and an alternative extension catalog separately | Medium | Reproducible builds, required functionality, and measured maintenance benefit. |
| 8 | Add Swift Testing or property-based tests where new cases benefit | Low per case | Better failure coverage without replacing useful existing cases. |

Keep compositor, container-backend, filesystem, and configuration-framework
migrations conditional on an unmet requirement or a measured maintenance problem.
No researched alternative establishes a general "best framework" independent
of those requirements.

## Validation and limits

This review inspected source and lockfiles and retrieved the linked primary
sources on the review date. Existing research helped locate requirements, but
current files take precedence when earlier same-day notes describe an older
working state. The pinned MkDocs documentation derivation built successfully and
its generated homepage was inspected at desktop width. A temporary Zensical
0.0.59 trial established the theme and project-root incompatibilities described
above; it did not modify repository files. No framework migration, dependency
update, system activation, network performance benchmark, recovery exercise, or
independent security audit ran as part of this review.

The tree contains extensive pre-existing edits. The submodule baselines were
framework `11e4d9dfe816b9855ae9de8318734059d616d3a1`,
nix-seal `7f213a533ae7e626416de1e17c41f25bfc145674`, and
packages `e2f597a2fc77ff2551ac5612086cb57c5cb8e554`, each with local modifications.
The recommendations apply to the inspected files, not just those commits.

Validation passed for Markdown with rumdl 0.2.64, all 36 repository-relative
links, whitespace, and a targeted Gitleaks scan using the repository's
publication policy.
Two independent reviewers checked the integrated report. Their corrections
clarified that deploy-rs serves the remote NixOS target and stated nix-seal's
current readiness limitation explicitly. Both corrections are included above.
No files were staged or committed, and no external publication occurred.
