# Working on nix-conf

This repository selects and configures workstation features. Start with the
affected host or home profile, then follow its selected modules to the behavior
being changed. The [glossary](CONTEXT.md) distinguishes those concepts.

## Repository boundaries

The root repository owns workstation configuration and integration. The three
submodules are separate repositories with their own checks and release history:

| Change | Owning repository |
| --- | --- |
| Host policy, home profiles, feature selection, integration | This repository |
| Package recipes and source updates | `pkgs/`, the nixpkgs-personal repository |
| Target discovery and module composition | `nix-config-framework/` |
| Secret-management implementation | `nix-seal/` |

Read the owning repository's instructions before editing it. Keep its changes
and validation separate from the root's gitlink update. A root diff shows only
the submodule revision, not the code inside it. Check `git status` in each
affected repository before staging; existing staged and unstaged work may belong
to another task.

## Configuration conventions

- Select reusable features in the target's `default.nix`. Put target-specific
  settings and configuration assets in its `local/` tree. That tree auto-imports
  Nix files, so each Nix file must be a module. Export target-specific helper
  functions through the module's `lib` option. Reserve `lib/` for helpers used
  across many locations or with a clear reuse case across future modules. Keep
  feature-specific functions in the caller's `let`, or in a nearby file when
  several modules in that feature need them.
  Place reusable configuration beside its owning module and inactive experiments
  in scratch storage.
- Place reusable system, user, or cross-platform behavior in the matching tree
  under `modules/`. Follow the [framework's selector and shared-module
  contracts](nix-config-framework/README.md#layout-and-selectors) before adding
  a module or changing a directory's `default.nix`.
- Give each setting one owner. Use explicit module options for real variations
  between targets. When overriding upstream behavior, explain the constraint
  and what would allow the override to be removed.
- Before adding, changing, or retiring a package or module override, read and
  follow the [override layout and lifecycle](overlays/README.md). This includes
  source rewrites and `disabledModules` replacements that repair upstream behavior.
  Temporary fixes require registry entries and review guards; reusable package
  variants retain their owning repository.
- Keep operational login names and hostnames accurate in configuration. Follow
  the [publication policy](docs/publication.md) when referring to them in prose.
- Keep private keys and plaintext credentials outside the repository and Nix
  store. Use the repository's sealed-secret integration and
  [secret-management guide](docs/secrets.md) for changes involving secrets.

## Validation

Choose the smallest check that exercises the changed behavior. Test observable
configuration, generated output, or a command's public behavior; obtain expected
results from the requirement or an independent fixture. For a bug, show that the
reproduction fails before the fix and passes after it. A successful evaluation
does not prove a package builds or a running service behaves correctly.

Discover current checks in `flake/dev/checks.nix` and
`flake/dev/platform-checks.nix`. Formatting and hook definitions live in
`flake/dev/formatter.nix` and `flake/dev/git-hooks.nix`; use them as the authority
instead of maintaining a second list of tool settings here.

Use `nix develop` for the pinned tools and `just --list` for repository commands.
`just hooks` installs the configured hooks in the current clone. Run focused
checks first, then the broader checks required by the changed area. Nix's Git
source filtering omits untracked files, so include new source files deliberately
before claiming an evaluation checked them.

Follow the desktop build-placement rule in [AGENTS.md](AGENTS.md). Darwin builds
and native runtime checks need a suitable Darwin host. State which platform was
tested and whether the result covers evaluation, build, or activation. Treat
activation and deployment as separate actions with the task's intended scope.

For documentation-only changes, check Markdown, relative links, whitespace,
ignore rules, and publication safety. A desktop system rebuild adds no evidence
for such a change.

## Hosted package builds

Native package CI reads the hosted-build exclusions from
`pkgs/.github/ci-policy.json`, the same local input used by the root flake.
Keep this policy in the package repository instead of maintaining a second list.
Missing or invalid policy stops selection; unavailable base history still applies
the exclusions. Publish the package submodule's policy commit with the root
gitlink update so CI receives both changes.
The macOS job narrows candidates to its representative outputs before applying
the same exclusions and derivation comparison as Linux.

These exclusions govern CI package selection, not every Nix build. Personal host
builds, remote builders, and `just fonts-check` can still build packages selected
by the configuration. Their upstream terms remain applicable. The exclusions do
not mean every private build is prohibited, or that private use is automatically
permitted. See the [package licensing policy](pkgs/docs/package-licensing.md).

Before adding a hosted integration check, review its dependencies as well as its
named target: a check or system closure can pull in an excluded package indirectly.
Current CI font-rendering checks use the core font selection; the full-collection
font-check app is a separate local command. Full host closures remain evaluation
only in hosted CI. Cache download configuration does not publish outputs; review
permissions separately before adding cache uploads or release artifacts.

## Work records and review

Use the [workflow guide](docs/agents/workflows.md) to choose a skill and the
[tracker guide](docs/agents/issue-tracker.md) to find its requirements. Routine
work can use the user's request directly; it does not need an issue or ADR.

Before committing, inspect the staged patch and include only the intended task's
changes. For a review, name the exact base, repositories, and source of acceptance
criteria. Report standards findings separately from requirements findings.
Describe what changed, how it was verified, and any remaining runtime checks.

Report vulnerabilities through [SECURITY.md](SECURITY.md).
