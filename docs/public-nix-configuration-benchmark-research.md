# Public Nix configuration benchmark

Reviewed: 2026-09-11, with API retrievals on 2026-09-12 UTC. Scope: public workstation configurations, reusable
configuration projects, and selected infrastructure repositories across GitHub,
GitLab, Codeberg, SourceHut, and self-hosted forges.

## Answer

The strongest next investment is making workstation reliability and recovery
verifiable at a specific revision. The current checkout already has the public
starter, guide, native CI declarations, and recipe tests recommended in the
September 10 comparison. Those are implemented locally; their presence does not
establish that the published default branch or every supported platform passes.

There is no defensible universal ranking of public Nix configurations. A fleet,
a desktop showcase, and a starter solve different problems. This investigation
uses reliable, reusable Linux and macOS workstations as the primary comparison.
Popularity helps discovery; source quality, operational evidence, and outsider
usability decide what is worth adopting.

The recommended order is:

1. Complete the existing backup, restore, and boot-recovery work with an attended drill.
2. Tie full native builds and desktop workflow checks to the exact candidate source.
3. Finish public-interface coverage and validate the existing guide with outside readers.
4. Extend existing storage freshness alerts to broader service health and verify delivery.
5. Extend application recovery contracts and repeatable performance measurements.

A small graphical demo, hardware onboarding, and generated feature documentation
are useful next features. More compositors, server applications, or a framework
rewrite need a specific use case before they deserve maintenance commitments.
This report proposes work; it does not implement or deploy those recommendations.

## Method and local baseline

The local baseline is root commit
`7fd38c80a2aabdb16674fba7231496fa4a575bee` plus the working tree inspected on the
review date. That working tree includes ongoing changes to the public starter and guide,
storage, CI, Python tests, and desktop configuration. Findings about those files describe
the checkout, not necessarily the published default branch or a deployed system.

The inspected submodule revisions were:

| Repository | Revision |
| --- | --- |
| Configuration framework | `11e4d9dfe816b9855ae9de8318734059d616d3a1`, locally modified |
| Secret manager | `7f213a533ae7e626416de1e17c41f25bfc145674`, locally modified |
| Package repository | `e2f597a2fc77ff2551ac5612086cb57c5cb8e554`, also locally modified |

The September 10 tables retain their original dated observations and pinned
sources. The refresh sections identify newly retrieved evidence separately.
GitHub API access worked in this refresh, so selected exact star counts supersede
older displayed counts only for the named projects. Fresh source inspection
confirmed the selected Mic92 build inventory, Blueprint consumer checks,
Oddlama health declarations, and nix-community alert rules.

Discovery used search, forge APIs, repository documentation, and source files.
GitHub candidates were inspected in shallow checkouts outside this repository;
other forges were inspected through read-only HTTP and Git requests. No external
repository's code was executed. Selected source links identify immutable
revisions. Branch links and documentation sites are dated observations.

This is a purposive sample, not an enumeration of every public Git repository.
It includes prominent desktop configurations, active technical references, and
less popular projects with useful operational designs. Mirrors are not separate
quality votes. An inspected workflow proves what its code requests; it does not
prove recent CI success or an author's running machine state.

## What this repository already does

| Area | Local evidence | Assessment |
| --- | --- | --- |
| Configuration structure | [Repository guide](../CONTRIBUTING.md), [framework exports and selector contracts](../nix-config-framework/README.md) | Separate ownership for packages, composition, secrets, and workstation policy. Typed module exports already exist. |
| Linux and macOS | [Flake](../flake.nix), [platform contracts](../flake/dev/platform-checks.nix) | NixOS, nix-darwin, and attached Home Manager environments. Three check platforms do not imply three complete workstation targets. |
| CI and updates | [CI matrix](../.github/workflows/ci.yml), [Dependabot](../.github/dependabot.yml) | Native checks on two Linux architectures and Apple Silicon; weekly lock, submodule, and Actions updates. Hosted CI intentionally excludes full host closures. |
| Behavioral checks | [Generated configuration checks](../flake/dev/generated-config-checks.nix), [storage VM](../tests/storage/install.nix), [test tree](../tests/) | Tests go beyond formatting and evaluation. The storage fixture exercises cold boot, missing data keys, backups, restoration, and unavailable destinations. This review did not run them. |
| Secrets and publication | [Secret manager](../nix-seal/README.md), [release controls](../nix-seal/docs/release.md), [publication policy](publication.md) | Signed artifacts, runtime secret delivery, documented release controls, and publication checks. The secret manager describes itself as an early pre-release project; complexity is not evidence of independent assurance. |
| Desktop integration | [Desktop modules](../modules/home/desktop/), [theme targets](../modules/shared/stylix/targets/), [macOS modules](../modules/home/macos/) | Broad existing integration, with font, browser, and window-management tests. Another bar, launcher, or theme system is not an obvious gap. |
| Change safety | [Deployment](../flake/deploy.nix), [activation diff](../hosts/nixos/desktop/local/system.nix), [boot counting](../modules/nixos/boot/systemd/default.nix) | Remote desktop builds, generation diffs, and boot fallback mechanisms exist. They are not equivalent to proving application health after activation. |
| Observability | [Telegraf](../hosts/nixos/desktop/local/observability.nix), [storage health](../hosts/nixos/desktop/local/storage/health.nix) | Storage already detects missing or overdue backup/restore receipts and stale health reports, with deduplicated desktop notifications. Telegraf separately exposes a loopback Prometheus endpoint for a future collector. Extend these mechanisms and verify delivery; freshness detection is not wholly missing. |
| Recovery readiness | [Storage options](../hosts/nixos/desktop/local/storage/default.nix), [backup destinations](../hosts/nixos/desktop/local/storage/backups.nix), [storage contracts](../flake/dev/storage-checks.nix), [boot policy](../hosts/nixos/desktop/local/security-secure-boot.nix) | The encrypted layout is opt-in, backup destinations default to empty, and Secure Boot and measured boot are explicitly disabled in host policy. These are implemented capabilities awaiting operational completion, not established protection. |
| Public entry point | [Starter](../templates/starter/flake.nix), [guide](README.md), [support table](guide/support.md), [CI](../.github/workflows/ci.yml) | Independent Home Manager starter on three declared platforms and an x86 Linux console VM now exist. CI copies the candidate starter and builds its own locked checks. A graphical workstation demo and a complete neutral Darwin system example remain separate extensions. |
| Consumer coverage | [Recipe tests](../tests/public-guide/recipes.nix), [public exports](../flake/public-guide.nix), [Git recipe](guide/git.md) | The current root tests exercise documented source-file imports with current inputs. They do not exercise root typed exports or initialize the root template through its exported name. The standalone starter intentionally has no root framework dependency. |
| Performance work | [Desktop performance follow-up](desktop-performance-research.md#implementation-follow-up) | Existing work records alternating evaluator trials and I/O VM checks, with activation and loaded responsiveness limits stated. The remaining gap is a repeatable revision-to-revision benchmark and regression budget, not the absence of performance investigation. |

Storage alert logic deserves explicit credit. The [backup helper](../hosts/nixos/desktop/local/storage/backup-helper.py)
tracks backup, integrity, restore, cold-restore and recovery-drill freshness.
The [health helper](../hosts/nixos/desktop/local/storage/health.py) rejects stale
reports and deduplicates desktop warnings; [tests](../tests/storage/test_backup.py)
check missing receipts and failure after recent success. The remaining question
is operational provisioning, delivery and wider service coverage, not whether
the project understands stale-success monitoring.

The recovery distinction matters most. An empty destination set creates no
backup jobs. The current storage contract even asserts that the evaluated
migration has no Restic backups. This does not establish that no external backup
exists; it establishes that this checkout does not configure one. Similarly,
the checked-in boot policy is not a live firmware inspection.

## Public repositories worth studying

### GitHub comparison set, September 10 snapshot

Stars below are the counts displayed by GitHub pages retrieved on 2026-09-10, rounded where GitHub rounds them. Browser results may reflect cached pages. The unauthenticated GitHub API returned HTTP 403 rate-limit errors, so these are not precise real-time API counts. Stars measure attention, not reliability. Tip dates and immutable source links come from shallow Git checkouts; commit timestamps are author-controlled and are not evidence of a successful build.

| Project | Type | GitHub stars shown | Retrieved default-branch tip date | Concrete evidence and lesson |
| --- | --- | ---: | --- | --- |
| [Misterio77/nix-starter-configs](https://github.com/Misterio77/nix-starter-configs) | Template | 3.8k | 2026-04-23 | Minimal and standard templates; the standard template exposes packages, overlays, NixOS and Home Manager modules with comments explaining each output. [Pinned source](https://github.com/Misterio77/nix-starter-configs/blob/fe4c4b136e0e073c71d8190a791ba03ccb47c5ac/standard/flake.nix). Use progressive disclosure: a small starting point and a richer example. The enclosing repository formatter input is older than the template inputs; inspect the template itself. |
| [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config) | Template + personal configuration | 3.6k | 2026-09-09 | Separate starter and starter-with-secrets templates, explicit installation/customization steps, and a template build workflow. [Pinned source](https://github.com/dustinlyons/nixos-config/blob/524547908a4218cb397f4814ced49f254ec82bc5/templates/starter/flake.nix). Strong onboarding comparison. Its build workflow initializes the remote default template without binding it to the checked-out revision; copy the consumer-testing idea while improving revision provenance. |
| [mitchellh/nixos-config](https://github.com/mitchellh/nixos-config) | Personal developer workstation | 3.1k | 2026-09-05 | Documents a macOS host plus NixOS development VM workflow, VMware/UTM setup, bootstrap stages, and WSL image export. [Pinned source](https://github.com/mitchellh/nixos-config/blob/cbc3129d50c6c20a59d8ac24d53323ffa0294507/README.md). A focused, coherent workflow is a stronger comparison than raw option count. Maintainer explicitly prioritizes a working personal setup over optimization. |
| [Aylur/dotfiles](https://github.com/Aylur/dotfiles) | Personal desktop / presentation | 3.1k | 2026-08-04 | Current README delegates shell details to the separate marble-shell project; the flake imports a local marble development input. [Pinned source](https://github.com/Aylur/dotfiles/blob/35e29f2b29d23a15f377baa0df7c84ad0f962b0f/flake.nix). Visual inspiration only at this revision: the machine-local input means the checkout is not a portable outsider demo. |
| [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config) | Personal workstation + homelab | 2.1k | 2026-09-10 | Linux/macOS configurations, operational dashboards and alerts, and expression tests including firewall settings across every declared NixOS configuration. [Pinned source](https://github.com/ryan4yin/nix-config/blob/aab819f7331ebc1d4296a5ef92e0379bbd777082/outputs/x86_64-linux/tests/security-firewall/expr.nix). Compare explicit fleet-wide invariants and operational documentation. Private secrets and hardware choices still constrain outsider deployment. |
| [hlissner/dotfiles](https://github.com/hlissner/dotfiles) | Personal workstation + tooling | 1.9k | 2026-09-10 | The hey command organizes build, sync, profile analysis, hooks and tests; test/nixos collects independently addressable library/module suites. [Pinned source](https://github.com/hlissner/dotfiles/blob/8041e4d640380a96ec755e79eeb46ff6ad3b61ca/test/nixos/default.nix). Useful model for a coherent operator interface and focused tests, without evidence that its whole-system quality exceeds this project. |
| [fufexan/dotfiles](https://github.com/fufexan/dotfiles) | Personal Wayland workstation | 1.1k | 2026-09-09 | Flake-parts configuration ties Hyprland plugins and related compositor dependencies to common inputs; includes custom theme modules and gaming/WSL inputs. [Pinned source](https://github.com/fufexan/dotfiles/blob/d4ee572ea3a332a09b2435850d33804f87e9b3b6/flake.nix). Study dependency alignment in a desktop stack; screenshots/popularity do not establish runtime correctness on different hardware. |
| [gvolpe/nix-config](https://github.com/gvolpe/nix-config) | Personal desktop / reference | 1.1k | 2026-09-10 | Documents Niri, Hyprland and XMonad environments, separate Home Manager outputs, and the exported packages and outputs. [Pinned source](https://github.com/gvolpe/nix-config/blob/265041cba89ccae5e4c7e4cf39f5d5bd13eb6638/README.md). A navigable feature catalog and clearly named variants are worth emulating; supporting three window managers is optional scope. |
| [divnix/digga](https://github.com/divnix/digga) | Framework, historical comparison | 1.0k | 2024-05-17 | Utility library for composing shell, home and host environments; default branch tip retrieved here is from May 2024. [Pinned source](https://github.com/divnix/digga/blob/117be8023d7615f1603cc99e0a5d4891f7b508a4/README.md). Retain as historical design evidence. Do not recommend migration on popularity alone or describe it as a currently active leader. |
| [sioodmy/nixus](https://github.com/sioodmy/nixus) | Personal configuration; now sioodmy/nixus | 921 | 2026-07-02 | Current flake exports packages, formatter, dev shells and NixOS modules; its editor input uses a machine-local path. [Pinned source](https://github.com/sioodmy/nixus/blob/9551ed3112fe6e8ce26700ef63493cb51bc20ecc/flake.nix). Repository description emphasizes evaluation speed, but no comparative benchmark was established. Do not repeat speed superiority as a measured fact. |
| [Mic92/dotfiles](https://github.com/Mic92/dotfiles) | Personal fleet + reusable tools | 776 | 2026-09-10 | Checks gather selected Linux/macOS system closures, packages and package.tests, development shells, and Home Manager outputs. [Pinned source](https://github.com/Mic92/dotfiles/blob/9dbd4f1c430fb7240b4dba03dc3101c6f778dac4/checks/flake-module.nix). Strong build-coverage design: make the expected output matrix explicit, including exclusions. Exporting modules and standalone applications also gives outsiders narrower consumption paths. |
| [ryan4yin/nix-darwin-kickstarter](https://github.com/ryan4yin/nix-darwin-kickstarter) | macOS template | 662 | 2026-06-03 | Separates a minimal starting configuration from a rich demo and explains their different intended uses. [Pinned source](https://github.com/ryan4yin/nix-darwin-kickstarter/blob/dca08d64f61a99ba05eb902c4e7af6a1181d32cf/README.md). A Linux/macOS project benefits from a dedicated short macOS onboarding path with its own prerequisites and first-build instructions. |
| [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config) | Personal multi-host reference; GitHub mirror | 644 | 2026-08-31 | README describes multi-user Linux/macOS composition, remote bootstrap, YubiKey workflows and backups; repository now says it is mirrored from Codeberg. [Pinned source](https://github.com/EmergentMind/nix-config/blob/a8ba4f4b6746466119b3c9f62befac97b9427cd5/README.md). Good teaching and architecture-navigation comparison. Count this as one project across forges; features described in README are source claims, not tests run here. |
| [numtide/blueprint](https://github.com/numtide/blueprint) | Framework + templates | 471 | 2026-09-02 | Folder-to-output conventions, reusable templates and template CI on Linux/macOS using the checked-out blueprint as an overridden input. [Pinned source](https://github.com/numtide/blueprint/blob/8be75245e274a789b87cc4df542abbcd8c5e7f93/.github/workflows/templates.yml). Best consumer-testing pattern in this sample: verify each generated/example project against the change under review. Blueprint itself calls its status experimental. |
| [NotAShelf/nyx](https://github.com/NotAShelf/nyx) | Archived personal reference | 438 | 2024-08-05 | Extensive module/role documentation and exported modules/templates, but explicitly abandoned and archived on 2024-08-05. [Pinned source](https://github.com/NotAShelf/nyx/blob/d407b4d6e5ab7f60350af61a3d73a62a5e9ac660/README.md). Historical architecture and presentation reference only. Current compatibility, maintenance and security are not established. |
| [oddlama/nix-config](https://github.com/oddlama/nix-config) | Personal workstation + homelab | 273 | 2026-08-31 | Generates HTTP monitoring targets from Nginx upstream declarations with expected response status/body; broader configuration includes microVM services and shared globals. [Pinned source](https://github.com/oddlama/nix-config/blob/a3854ea1c1b253b1cf58d29a7eef799a6ce5a582/modules/nginx-upstream-monitoring.nix). Worth studying for coupling service definition to health checks so monitoring cannot silently drift from deployed inventory. |
| [NobbZ/nixos-config](https://github.com/NobbZ/nixos-config) | Personal configuration + update automation | 271 | 2026-09-10 | Update workflow produces a lock artifact, restores it into package/check matrix jobs, and creates/merges an update PR after dependencies. [Pinned source](https://github.com/NobbZ/nixos-config/blob/78716e5c253ed6a03230cc13d8b0da26cadd913f/.github/workflows/flake-update.yml). Useful update-artifact provenance pattern. Do not copy unchanged: generic flake-check is continue-on-error and the final step auto-merges. |
| [nix-community/infra](https://github.com/nix-community/infra) | Community operational infrastructure | 178 | 2026-09-09 | Monitoring rules detect absent backup telemetry, overdue successful tasks, old nixpkgs inputs, disk pressure and hardware errors. [Pinned source](https://github.com/nix-community/infra/blob/34349c9ab4271fa790affce402709e1485462bab/modules/nixos/monitoring/alert-rules.nix). A stronger operations benchmark than stars imply: monitor missing evidence and stale success, alongside current service failures. |

### Other forges and infrastructure references, September 10 snapshot

Counts below came from public forge APIs on September 10. They are not
comparable across forge communities. SourceHut does not provide an equivalent
star count here. A mirror may omit the originating forge's CI and discussions.

| Project | Forge and observed popularity | Evidence and useful lesson |
| --- | --- | --- |
| [Zaney/zaneyos](https://gitlab.com/Zaney/zaneyos) | GitLab, 246 stars; tip 2026-09-09 | [README and guides](https://gitlab.com/Zaney/zaneyos/-/blob/a87d77e12be82680e269b71268df62734123f36a/README.md), GPU profiles, and a [central customization file](https://gitlab.com/Zaney/zaneyos/-/blob/a87d77e12be82680e269b71268df62734123f36a/hosts/default/variables.nix) make the desktop approachable. Borrow the feature guide, keybinding reference, and clear customization path. Its README also documents a first-login workaround, so presentation does not establish flawless startup. |
| [Scrumplex/flake](https://codeberg.org/Scrumplex/flake) | Codeberg, 16 stars; tip 2026-09-10 | A [typed Alloy discovery module](https://codeberg.org/Scrumplex/flake/src/commit/5967366cf69b7e517c15c04ae01a18ef6255bea0/nix/modules/base/alloy-discovery.nix) generates scrape definitions from configuration. The [flake](https://codeberg.org/Scrumplex/flake/src/commit/5967366cf69b7e517c15c04ae01a18ef6255bea0/flake.nix) also composes Linux and Darwin targets. Borrow declarative collector integration; its README says composition is being refactored, so do not treat that layout as settled. |
| [sensei/nixos](https://codeberg.org/sensei/nixos) | Codeberg, 23 stars; tip 2026-09-10; provenance corrected below | [Build gate](https://codeberg.org/sensei/nixos/src/commit/bf80049477ec4d5cd77e8a74612b5cdcffebe491/.forgejo/workflows/deploy-gate.yaml) builds selected host closures before advancing a candidate ref; [release workflow](https://codeberg.org/sensei/nixos/src/commit/bf80049477ec4d5cd77e8a74612b5cdcffebe491/.forgejo/workflows/deploy-release.yaml) later promotes that ref. Borrow the explicit build-versus-release boundary. A timed promotion alone does not prove runtime health. The September 11 refresh corrects the earlier description of Codeberg as a mirror. |
| [averagechris/dotfiles](https://git.sr.ht/~averagechris/dotfiles) | SourceHut; inspected revision `3187327dc3c2` | The [performance audit](https://git.sr.ht/~averagechris/dotfiles/blob/3187327dc3c2a7571e54d80f105217f8a80728db/docs/flake-performance-audit.md) separates evaluation, substitution, and builds; reports elapsed time and peak memory; and documents bounded hosted CI plus an operational build/cache worker keyed to a revision. Very relevant to this repository's full-closure placement constraints. Its reported results were not reproduced here. |
| [misterio/nix-config](https://git.sr.ht/~misterio/nix-config) | SourceHut; inspected revision `c1ee5c7310e3` | [README](https://git.sr.ht/~misterio/nix-config/blob/c1ee5c7310e3993b13522714d8c9cbc39d47d7eb/README.md) describes persistence, mesh networking, Hydra and shared builders; [flake](https://git.sr.ht/~misterio/nix-config/blob/c1ee5c7310e3993b13522714d8c9cbc39d47d7eb/flake.nix) exports modules and templates. Treat this as a historical design reference: the README includes 2022 desktop material and this investigation did not establish its current maintenance date. Do not count it as the separate starter project's current implementation. |
| [chvp/nixos-config](https://git.chvp.be/chvp/nixos-config) | Self-hosted forge, source inspected through its GitHub mirror | The [build/cache script](https://github.com/chvp/nixos-config/blob/e5fbeddbe09e70766618d2c698ea7f238aa0c215/build_and_cache_all.sh) builds declared systems and development shells, uploads successful outputs, and preserves aggregate failure status. Useful implementation reference if a private operational cache becomes necessary. |
| [Clan](https://git.clan.lol/clan/clan-core) | Self-hosted Gitea; framework reference | Current [backup documentation](https://clan.lol/docs/unstable/guides/backups/intro-to-backups) separates application state declarations from backup providers and describes service-aware restoration. Borrow that ownership boundary for stateful applications. Adopting the whole fleet framework is a separate scope decision. The linked unstable documentation can change. |

Two further repositories were screened but are not recommended as present-day
implementation baselines. [davidak/nixos-config](https://codeberg.org/davidak/nixos-config/src/commit/b7b96e9214ba44b35940d9854def5752390a83bd/README.md)
has useful per-machine documentation, 15 Codeberg stars, and a July 2026 tip,
but its README still shows 20.09 channel setup. The GitLab API for
[vdemeester/home](https://gitlab.com/vdemeester/home) returned last activity in
November 2024 and two stars; its broad reference list helped discovery but does
not establish current operational quality. TVL's forge was also considered but
could not be retrieved, so it contributes no findings.

### Refreshed GitHub evidence and additional references

The six exact counts below came from the public GitHub repository API during
this refresh. All six reported `archived = false`. They are a small refreshed
subset, not a new popularity ranking. Pinned links identify the source reviewed;
a recent commit and an active repository flag do not establish passing CI.

| Project | API stars | Refreshed primary evidence | Comparison result |
| --- | ---: | --- | --- |
| [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config) | 2,053 | [Firewall expression](https://github.com/ryan4yin/nix-config/blob/a71472012cc9bcaab6e2e935b7b71773e967aad4/outputs/x86_64-linux/tests/security-firewall/expr.nix) enumerates all NixOS configurations. | Use target-inventory invariants where a policy applies to every target. This expression alone is not a live firewall test. |
| [hlissner/dotfiles](https://github.com/hlissner/dotfiles) | 1,942 | [Operator commands](https://github.com/hlissner/dotfiles/tree/a0ee595becc216ce6f9b5e45dc59b7b0b093029c/bin/hey.d) organize build, profile, test and update tasks. | The existing `just` interface can provide the same discoverability. Another wrapper language is unnecessary. |
| [Mic92/dotfiles](https://github.com/Mic92/dotfiles) | 779 | [Check inventory](https://github.com/Mic92/dotfiles/blob/d8f53aee3ea2f5a06c31fb75fd180fcaa9dec3b5/checks/flake-module.nix) combines selected Linux/Darwin closures, package tests, shells and homes. | Make full-output coverage explicit on permitted native builders, preserving documented exclusions. |
| [numtide/blueprint](https://github.com/numtide/blueprint) | 472 | [Template workflow](https://github.com/numtide/blueprint/blob/8be75245e274a789b87cc4df542abbcd8c5e7f93/.github/workflows/templates.yml) checks each template on Linux/macOS with the local candidate as its Blueprint input. | Adopt this pattern for an exported-module consumer, while retaining the root's independent starter. |
| [oddlama/nix-config](https://github.com/oddlama/nix-config) | 273 | [Monitoring module](https://github.com/oddlama/nix-config/blob/a3854ea1c1b253b1cf58d29a7eef799a6ce5a582/modules/nginx-upstream-monitoring.nix) derives probes from enabled upstream declarations and expected responses. | Couple important service declarations to meaningful probes; adapt to workstation services rather than copy the whole homelab. |
| [nix-community/infra](https://github.com/nix-community/infra) | 178 | [Alert rules](https://github.com/nix-community/infra/blob/6d9ddcdfc42fc0d449fc620de9ed1115b2ba994d/modules/nixos/monitoring/alert-rules.nix) detect absent task data, stale success, disk pressure and old inputs. | Generalize existing storage freshness checks to other important services and verify alert delivery. The broader Telegraf endpoint still needs a collector if used for this purpose. |

Additional inspected sources expand the sample beyond the earlier shortlist.
Their popularity was not normalized against the API subset above. The first
three are configurations; the last two are supporting projects with useful
implementation patterns.

| Project and inspected revision | Concrete strength | Limitation and local implication |
| --- | --- | --- |
| [Misterio77/Foundry](https://github.com/Misterio77/Foundry/tree/e09ecf80d761b92c31a28d00b649e3339a43dabb), current destination of `Misterio77/nix-config` | [Hydra jobs](https://github.com/Misterio77/Foundry/blob/e09ecf80d761b92c31a28d00b649e3339a43dabb/hydra.nix) derive host and home build outputs; [upgrade policy](https://github.com/Misterio77/Foundry/blob/e09ecf80d761b92c31a28d00b649e3339a43dabb/hosts/nixos/common/global/auto-upgrade.nix) disables its timer for source without a clean Git revision. | Its [upgrade module](https://github.com/Misterio77/Foundry/blob/e09ecf80d761b92c31a28d00b649e3339a43dabb/modules/nixos/hydra-auto-upgrade.nix) links built outputs to source and shows diffs, but does not supply an application-health gate after activation. Borrow source identity and coverage; automatic switching is a separate policy. The older SourceHut copy is historical. |
| [sodiboo/system](https://github.com/sodiboo/system/tree/8f22bf5bb3789917be22da8848903d16ff92bcc4) | [Graphical VM variant](https://github.com/sodiboo/system/blob/8f22bf5bb3789917be22da8848903d16ff92bcc4/personal/vm.mod.nix) provides VM-specific shortcuts and instructions, graphical QEMU, and disables personal VPN services. | Its own welcome text acknowledges intermittent compositor startup and a fixed keyboard layout. A useful demo mechanism, not verified reliability. Add a small graphical demo only with boot, terminal, launcher and shutdown checks. |
| [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config/tree/a8ba4f4b6746466119b3c9f62befac97b9427cd5), Codeberg origin and GitHub mirror | [MicroVM guide](https://github.com/EmergentMind/nix-config/blob/a8ba4f4b6746466119b3c9f62befac97b9427cd5/microvms/README.md) describes per-agent shares and routing; [network module](https://github.com/EmergentMind/nix-config/blob/a8ba4f4b6746466119b3c9f62befac97b9427cd5/modules/hosts/nixos/microvms/network.nix) derives allowed host ports from VM declarations. | The guide documents persistent guest disks and a readable shared host Nix store. The [README](https://github.com/EmergentMind/nix-config/blob/a8ba4f4b6746466119b3c9f62befac97b9427cd5/README.md) leaves Darwin support as-is on a separate branch in 2026. Treat agent microVMs as an optional feature with access-boundary tests, not evidence of stronger current macOS support. |
| [sodiboo/niri-flake](https://github.com/sodiboo/niri-flake/tree/9ee3e13b60643448228353097880521658b2fe0e), supporting module | [Flake](https://github.com/sodiboo/niri-flake/blob/9ee3e13b60643448228353097880521658b2fe0e/flake.nix) validates generated settings with the selected Niri binary and generates option documentation. | [README](https://github.com/sodiboo/niri-flake/blob/9ee3e13b60643448228353097880521658b2fe0e/README.md) excludes Home Manager configurations from its automatic testing and notes version compatibility limits. This reinforces the root's existing [generated-file checks](generated-file-checks.md); add uncovered formats rather than replace the current desktop. |
| [nix-community/srvos](https://github.com/nix-community/srvos/tree/ee2f679bdc7324f90dc73c0f22f2d5fab25b1b33), supporting profiles | [Development composition](https://github.com/nix-community/srvos/blob/ee2f679bdc7324f90dc73c0f22f2d5fab25b1b33/dev/default.nix) tests stable and unstable module combinations; [public flake](https://github.com/nix-community/srvos/blob/ee2f679bdc7324f90dc73c0f22f2d5fab25b1b33/flake.nix) separates development inputs. | Its [VM smoke test](https://github.com/nix-community/srvos/blob/ee2f679bdc7324f90dc73c0f22f2d5fab25b1b33/dev/checks.nix) waits for SSH, not broad service behavior. The root already [partitions development inputs](../flake/partitions.nix). Release-family compatibility tests are useful only for families explicitly supported. |

### Refreshed evidence from other forges

API counts below were retrieved on September 12 UTC, September 11 locally.
These communities have different audiences, so their star counts should not be
compared numerically with GitHub. SourceHut has no equivalent count here.

| Project | Forge/API stars | Refreshed primary evidence and practical lesson |
| --- | --- | --- |
| [Zaney/zaneyos](https://gitlab.com/Zaney/zaneyos) | GitLab, 246 | [README](https://gitlab.com/Zaney/zaneyos/-/blob/fb21c38bdc00eca4beb5e07c700e0ec76cf1ba30/README.md) and [variables](https://gitlab.com/Zaney/zaneyos/-/blob/fb21c38bdc00eca4beb5e07c700e0ec76cf1ba30/hosts/default/variables.nix) make shortcuts, shell-specific behavior, hardware profiles and defaults discoverable. The README also says its upgrade script was removed due to a problem. Borrow the clear feature guide, with separate tests of install and upgrade behavior. |
| [Scrumplex/flake](https://codeberg.org/Scrumplex/flake) | Codeberg, 16 | [Alloy discovery](https://codeberg.org/Scrumplex/flake/src/commit/5967366cf69b7e517c15c04ae01a18ef6255bea0/nix/modules/base/alloy-discovery.nix) provides typed scrape targets and labels, generates discovery JSON, and connects it to the collector when enabled. The root already exports metrics; a collector contract is the missing connection. This module alone does not establish alert delivery. |
| [sensei/nixos](https://codeberg.org/sensei/nixos) | Codeberg origin, 23 | [README](https://codeberg.org/sensei/nixos/src/commit/1808a6c0c466074dc3dbf73ae06a87f2bce1d392/README.md) links a GitHub mirror, identifies the maintained desktop, and labels retired configurations. [Build gate](https://codeberg.org/sensei/nixos/src/commit/1808a6c0c466074dc3dbf73ae06a87f2bce1d392/.forgejo/workflows/deploy-gate.yaml) builds selected comin hosts before moving the candidate reference. Later release promotion is separate from application-health evidence. Borrow explicit support status and source promotion boundaries. |
| [averagechris/dotfiles](https://git.sr.ht/~averagechris/dotfiles) | SourceHut | [CI tiers](https://git.sr.ht/~averagechris/dotfiles/blob/3187327dc3c2a7571e54d80f105217f8a80728db/scripts/ci-check-tiers.sh) separate host evaluation, selected builds and manual full builds. The [audit](https://git.sr.ht/~averagechris/dotfiles/blob/3187327dc3c2a7571e54d80f105217f8a80728db/docs/flake-performance-audit.md) records cache conditions, alternating trials and peak memory. Extend the root's workload queue with comparable reports. Its platform guard can exit successfully after skipping a tier; report skipped results explicitly in any local validation manifest. |
| [Clan](https://git.clan.lol/clan/clan-core) | Self-hosted framework, 47 | [State module](https://git.clan.lol/clan/clan-core/src/commit/662031f026ecdb4309fcc19b6df1f81b933d4d72/nixosModules/clanCore/state.nix) declares provider-independent folders and backup/restore hooks. [PostgreSQL integration](https://git.clan.lol/clan/clan-core/src/commit/662031f026ecdb4309fcc19b6df1f81b933d4d72/nixosModules/clanCore/postgresql/default.nix) uses temporary dump files before rename and restart handling around restoration. The [inspected PostgreSQL test](https://git.clan.lol/clan/clan-core/src/commit/662031f026ecdb4309fcc19b6df1f81b933d4d72/nixosModules/clanCore/postgresql/tests/flake-module.nix) checks SQL use, not a backup/restore cycle. Borrow state ownership, then add an actual application recovery test locally. |

The [sensei API](https://codeberg.org/api/v1/repos/sensei/nixos) reports that
Codeberg is not a mirror, consistent with its pinned README. This corrects the
original table's provenance; it does not establish a historical migration date.
The [EmergentMind Codeberg branch](https://codeberg.org/api/v1/repos/EmergentMind/nix-config/branches/dev)
was newer than the GitHub mirror inspected above. Its source was not re-audited,
so mirror-based implementation findings retain their pinned scope.

Codeberg browser pages were blocked, but public API file reads worked. SourceHut
raw files and refs were accessible while an individual commit page returned an
error; this refresh does not assign it a newly verified commit date. TVL remained
inconclusive after direct retrieval timeouts. It contributes no current quality
claim. These access limits prevent an exhaustive cross-forge comparison.

### Specific patterns to adopt and improve

| Pattern | Primary reference | Local implication |
| --- | --- | --- |
| Test every example as a downstream consumer of the candidate source | [Blueprint template workflow](https://github.com/numtide/blueprint/blob/8be75245e274a789b87cc4df542abbcd8c5e7f93/.github/workflows/templates.yml) | Retain current recipe and starter checks; add coverage of template extraction and any advertised typed-export consumer interface. |
| Give newcomers a small start and an optional richer configuration | [Misterio starter outputs](https://github.com/Misterio77/nix-starter-configs/blob/fe4c4b136e0e073c71d8190a791ba03ccb47c5ac/flake.nix), [Darwin kickstarter](https://github.com/ryan4yin/nix-darwin-kickstarter/blob/dca08d64f61a99ba05eb902c4e7af6a1181d32cf/README.md) | Keep the implemented independent starter; add richer examples only with explicit platform and runtime coverage. |
| State exactly which outputs receive build coverage | [Mic92 checks](https://github.com/Mic92/dotfiles/blob/9dbd4f1c430fb7240b4dba03dc3101c6f778dac4/checks/flake-module.nix) | Publish coverage boundaries and add native full-build evidence where hosted CI deliberately stops at evaluation. |
| Detect absent telemetry and stale successful work | [nix-community alert rules](https://github.com/nix-community/infra/blob/34349c9ab4271fa790affce402709e1485462bab/modules/nixos/monitoring/alert-rules.nix) | Preserve existing storage receipt/freshness checks; extend tested alerting to other critical services and connect the broader metrics collector when needed. |
| Generate health checks beside service definitions | [Oddlama upstream monitoring](https://github.com/oddlama/nix-config/blob/a3854ea1c1b253b1cf58d29a7eef799a6ce5a582/modules/nginx-upstream-monitoring.nix) | Important local services should declare a meaningful probe along with configuration. A running process is weaker evidence than a successful user operation. |
| Benchmark equivalent source and cache conditions | [SourceHut performance audit](https://git.sr.ht/~averagechris/dotfiles/blob/3187327dc3c2a7571e54d80f105217f8a80728db/docs/flake-performance-audit.md) | Extend the existing evaluator experiment into repeatable evaluation, closure-cost, and responsiveness comparisons before changing architecture or cache policy. |

Popular examples also contain designs to improve on. Dustin Lyons's
[template workflow](https://github.com/dustinlyons/nixos-config/blob/524547908a4218cb397f4814ced49f254ec82bc5/.github/workflows/build-template.yml)
initializes a remote default template rather than explicitly binding it to the
candidate checkout. NobbZ's
[update workflow](https://github.com/NobbZ/nixos-config/blob/78716e5c253ed6a03230cc13d8b0da26cadd913f/.github/workflows/flake-update.yml)
preserves an updated lockfile across jobs, but allows the generic flake check to
fail and later auto-merges. Borrow reproducible update inputs while retaining
blocking checks and this project's review policy.

## What would establish leadership

Use observable outcomes instead of a combined numerical score. This study did
not run the same workloads on every repository, so assigning scores would imply
comparability the evidence does not support. These targets are proposals for
future validation, not claims of present achievement.

| Dimension | Evidence that matters | Current position and next proof |
| --- | --- | --- |
| Outsider adoption | A fresh user completes the published path with no private inputs or maintainer intervention. | Starter and guide exist. Run a small pilot, record completion and blockers, and repair repeated failures. The [adoption research](project-adoption-research.md) proposes four of five readers as an initial target, not a measured success rate. |
| Reproducibility | Candidate source, lockfiles, submodule state and build outputs are tied together. | Public starter checks and native CI declarations exist. Record real runs and full workstation build evidence at the same source identity. |
| Reliability | Login, locking, portals, audio and other advertised workflows work after deployment. | Several feature-specific tests exist. A documented full-workstation acceptance run remains distinct from the console starter VM. |
| Recovery | Restore application state and credentials to a disposable or replacement target and verify a user operation. | Storage recovery fixtures exist, but the default host policy still disables the encrypted layout and selects no backup destinations. Verify configured protection and an attended recovery drill before claiming readiness. |
| Reuse and maintenance | Supported imports have consumer checks, compatibility boundaries and discoverable options. | Source-file recipes and typed exports exist with different coverage. Test only the interfaces actually promised and document their support scope. |
| Performance | Repeated comparable workloads measure latency, peak memory and build/transfer costs. | Evaluator measurements exist. Add revision comparison and foreground responsiveness under background work. |

### Additional features worth considering

These are scoped extensions, not prerequisites for being a good workstation
project. Their priority follows recovery and validation work.

| Feature | Why it is worth considering | Existing local baseline, cost and acceptance criterion |
| --- | --- | --- |
| Small graphical demo | [sodiboo/system VM](https://github.com/sodiboo/system/blob/8f22bf5bb3789917be22da8848903d16ff92bcc4/personal/vm.mod.nix) lets readers try the desktop before adopting a machine configuration. | The [starter VM](../templates/starter/vm.nix) is console-only. A new demo must boot without owner secrets, show shortcuts, launch its desktop and terminal, and shut down cleanly. This adds compositor and graphics test maintenance. |
| Complete neutral Darwin system example | [Darwin kickstarter](https://github.com/ryan4yin/nix-darwin-kickstarter/blob/dca08d64f61a99ba05eb902c4e7af6a1181d32cf/README.md) separates minimal setup from a richer demo. | The starter already builds Home Manager on Darwin; the [add-host guide](guide/add-host.md) points to upstream system setup. A full nix-darwin example would need its own native build and attended first-activation/recovery evidence. |
| Service-owned recovery declarations | [Clan backup model](https://clan.lol/docs/unstable/guides/backups/intro-to-backups) separates state declarations from storage providers. | Extend the existing [cold-backup implementation](../hosts/nixos/desktop/local/storage/backups.nix) with export/quiesce/restore hooks. Prove recovery of one database-backed application and a VM including its firmware and TPM state. Storage and credentials are prerequisites. |
| Generated option and feature reference | [niri-flake](https://github.com/sodiboo/niri-flake/blob/9ee3e13b60643448228353097880521658b2fe0e/flake.nix) derives option documentation from code. | The [public guide](README.md) is hand-authored and intentionally small. Generate details for a bounded set of supported features, with defaults, types, dependencies and examples; verify that source changes update the reference. |
| Release-family compatibility checks | [srvos composition](https://github.com/nix-community/srvos/blob/ee2f679bdc7324f90dc73c0f22f2d5fab25b1b33/dev/default.nix) exercises stable and unstable inputs. | The root uses unstable inputs while the starter pins a stable family. Test each claimed recipe against the supported families or explicitly narrow support. Each added family increases maintenance and build cost. |
| Isolated agent microVMs, conditional | [EmergentMind microVMs](https://github.com/EmergentMind/nix-config/blob/a8ba4f4b6746466119b3c9f62befac97b9427cd5/microvms/README.md) offer declared shares, secrets and routing. | The [virtualization decision](workstation-virtualization.md) currently specifies one persistent Windows guest and no Linux development VM. Preserve that decision unless a new workload requires isolation. Any later design needs tests of host access, secrets, egress and reset behavior; a shared Nix store is a deliberate visibility choice. |

## Prioritized improvements

The following acceptance criteria are proposed targets, not measurements or
claims that the project currently passes them. Effort is relative to the
existing code, and operational work depends on available hardware and storage.

| Priority | Improvement | Concrete completion criterion | Owner and effort |
| --- | --- | --- | --- |
| P0 | Complete recovery readiness | Selected backup destinations have recent verified restores; an application is recovered on a disposable target; recovery credentials and a previous boot generation work in an attended drill. Record revision and date without publishing private recovery material. | Root host integration; substantial operational work |
| P1 | Verify and release the existing starter | Record candidate-specific native results for all three declared starter platforms and the existing x86 VM. Have outside readers follow the guide from a fresh clone. Keep the console VM scope explicit. | Root examples, guide, CI; medium |
| P1 | Complete consumer boundaries | Extract `templates.starter` from the candidate source and run its checks. Add a separate neutral flake using advertised typed exports if those exports become a supported root recipe. A deliberate export or extraction defect must fail the relevant consumer test. | Root integration; medium |
| P1 | Feature and option catalog | Extend the existing guide with a bounded catalog naming each supported recipe, import interface, platforms, dependencies, persistent state and validation level. Generate typed option reference where practical. | Root documentation, framework generator only if shared; medium |
| P1 | Revision-specific native validation | A record ties a clean source revision, submodule revisions, lockfiles, platform, full build result, and runtime check result together. Failed or missing checks remain visible. | Root operational validation; medium to large |
| P2 | Broader service health and verified alert delivery | Retain existing storage freshness detection. Simulated missing telemetry, overdue restores, and stopped important services each reach the chosen notification channel. Test recovery transitions and behavior when no desktop session is available. | Root observability integration; medium |
| P2 | Performance regression budget | Extend existing measurements into repeatable reports for evaluation and peak memory, cache transfer, build and activation. Include foreground latency under background load; establish variance before choosing budgets. | Root development tooling; medium |
| P2 | Application recovery contracts | Stateful applications declare data, exclusions, export or quiesce steps, secret dependencies, and a restore check. Exercise at least one database-backed application and a VM. | Root reusable features and storage integration; substantial |
| P2 | Public release evidence | A release page distinguishes evaluated, built, VM-tested, and hardware-tested behavior. Review a small desktop walkthrough and keybinding reference for publication. | Root documentation and release process; medium |

### Preserve the independent starter and test the advertised interfaces

The current starter deliberately uses only Nixpkgs and Home Manager. That is a
useful teaching boundary. Its CI builds a copy from the candidate checkout with
its own committed lockfile. This already avoids the remote-default-template
problem identified in Dustin Lyons's historical workflow.
[Starter source](../templates/starter/flake.nix), [CI](../.github/workflows/ci.yml).

The three reuse guides advertise source-file imports using `flake = false`.
Their tests exercise those modules directly with the root's current inputs.
That is appropriate coverage of the module behavior. A separate consumer test
could additionally catch source packaging and transport mistakes by importing a
candidate source input exactly as documented. Template initialization should
also exercise `templates.starter`, since copying its directory bypasses that
export. [Git recipe](guide/git.md), [recipe checks](../tests/public-guide/recipes.nix),
[template export](../flake/public-guide.nix).

If the root's typed exports become a supported reuse path, add a distinct
consumer flake that imports those names and overrides its root input to the
candidate checkout. Blueprint demonstrates this dependency-override pattern.
Keep the existing independent tutorial. Do not make it fetch the full personal
flake and submodules just to demonstrate a shell configuration.

A richer graphical demo should remain small enough for the hosted package
policy and VM capacity. Its purpose is to demonstrate login, theming, locking,
portals and a few applications through ordinary reusable modules. Physical GPU,
suspend and macOS permission checks still need native evidence.

### Native validation should complement the current CI

Preserve the existing three-platform checks and resource limits. Add an
operational validation path for the exact source intended for deployment. The
full desktop closure must still build on the desktop host; Darwin realization
needs a suitable Darwin host. A general remote Linux builder is not a substitute
for either rule.

Separate the results for evaluation, build, dry activation, actual activation,
and runtime checks. Desktop checks should cover login, locking, audio, portals,
screen sharing, suspend/resume, display behavior, and rollback where supported.
Record hardware-dependent checks separately from VM checks. A successful
deploy-rs confirmation does not establish that every desktop workflow works.

Builds of unchanged revisions can reuse a successful record. Dirty source needs
an explicit source digest or a clear local-only label; a HEAD SHA alone does
not identify its contents. Automatic activation is a separate policy decision.

### Make feature state visible

Use a small status vocabulary in the catalog: available, selected, evaluated,
built, VM-tested, and hardware-verified. The disabled encrypted layout and boot
security options show why a single feature checkbox would be misleading.
Include the date and revision for evidence that becomes stale after updates.

The public guide now provides a short entry point and reusable recipes. Extend
it with a bounded feature catalog and generated option details. A reader should
be able to find the supported setting, its dependencies, and its evidence
without reading the full investigation history.

### Keep recovery knowledge beside its application

The existing cold-backup policy already excludes live VM and container data
from ordinary file backups and requires stopped writers for a separate capture.
Extend that design with application-specific exports and restore checks. A
successful file restore alone does not establish database consistency or that
a VM's disk, firmware, and virtual TPM state still match.

## Changes that do not currently justify their cost

- Replacing the framework solely to adopt a fashionable directory pattern.
  First demonstrate a broken composition contract, poor consumer ergonomics,
  or a measured evaluation cost.
- Replacing the secret manager merely because another configuration uses a
  different one. Assess maintenance, interoperability, recovery, and independent
  assurance. Its pre-release status belongs in public support claims.
- Adding impermanence as a quality badge. It can make undeclared state visible,
  but needs a complete persistence inventory and tested recovery. The existing
  storage migration should be completed first.
- Adding fleet orchestration, Kubernetes, public monitoring, or a service mesh
  without a workload that needs them. Their presence in a larger repository
  does not make a two-workstation configuration incomplete.
- Moving full personal closures into hosted CI or publishing a cache without
  checking capacity and the existing package-publication policy.
- Expanding supported platforms or desktop environments faster than they can
  be tested. A selectable module is not the same as a supported installation.

## Validation and limits

The September 11 refresh inspected the local source and documentation, queried
public forge metadata, and read selected upstream files at pinned revisions.
It did not evaluate or build Nix configurations, execute upstream tests,
activate a workstation, inspect live backup storage, or run a new performance
experiment. Existing test and performance notes are credited as prior evidence,
not checks repeated during this research. No universal superiority claim follows.

The only tracked file edited by this research is this report. Existing staged
and unstaged work was preserved, including the already-staged earlier version
of this file. The refresh remains unstaged. Raw upstream material and helper
research live outside the repository; the redacted task brief and before-image
are in ignored scratch storage.

The refresh passed the repository-configured Markdown rules with rumdl 0.1.94,
relative file and Markdown-anchor checks, whitespace checks, and a Gitleaks
directory scan of an isolated copy using the repository publication policy.
Scratch ignore rules were verified. An independent review of the captured report
delta found no standards or requirements defects. These are documentation checks,
not validation of the proposed system changes.

The original GitHub discovery used displayed, sometimes rounded or cached,
counts because unauthenticated requests were limited. Selected counts in the
refresh use API responses. Non-GitHub access limitations are recorded beside
those findings. Search coverage, mirrors and inaccessible CI constrain the
comparison. Neither stars nor commit timestamps establish runtime quality.
