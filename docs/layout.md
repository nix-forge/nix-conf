# Repository layout and naming

Start at the target's `default.nix` when changing a host or home profile. Follow
its selected feature to `modules/`, or its target-specific setting to `local/`.
The [contributor guide](../CONTRIBUTING.md) defines repository ownership and
validation. The [layout investigation](research/project-layout-research.md)
records the inventory, source evidence, and reasons for this organization.

## Source ownership

| Location | Contents |
| --- | --- |
| `hosts/{nixos,darwin}/<host>/default.nix` | System discovery metadata and reusable feature selection |
| `homes/<profile>/default.nix` | Home discovery metadata and reusable feature selection |
| `hosts/**/local/`, `homes/**/local/` | Personal hardware, accounts, preferences, secrets and integration policy |
| `hosts/shared/local/`, `homes/shared/local/` | Shared personal policy imported explicitly by its consumers |
| `modules/{nixos,darwin,home,shared}/` | Selectable reusable features, divided by module class |
| `flake/` | Flake outputs, deployment and integration composition |
| `flake/dev/` | Development environments and focused check definitions |
| `lib/` | Algorithmic or mathematical helpers and explicitly exported functions with multiple callers |
| `overlays/` | Input and package selection, permanent variants, registered temporary fixes |
| `scripts/` | Repository operations and formatter support |
| `tests/<domain>/` | Behavior suites, explicit native probes and nearby fixtures |
| `templates/` | Independently usable public examples and installer source templates |
| `site/` | Curated guide rendering and publishing configuration |

Package recipes belong to `pkgs/`, discovery to `nix-config-framework/`, secret
implementation to `nix-seal/`, and reusable homelab behavior to `nix-homelab/`.
These are independent Git repositories. Follow each repository's conventions
when changing its sources.

## Target-local files

Group local settings by the behavior they own. Existing desktop domains include
`gaming/`, `hardware/`, `homelab/`, `network/`, `observability/`, `security/`, and
`storage/`. The directory supplies context for short module names such as
`network/wireguard.nix`. Add a domain when several related files have a common
owner; a single clear file can remain at the target root.

Keep runtime sources with their owning feature. Music bootstrap and integration
scripts live under `local/homelab/music/scripts/`. Actual's CLI and lifecycle
scripts live under `local/homelab/actual/scripts/`. Credential importers and
their sibling SSH workers live under `local/homelab/credentials/`. Host-wide
activation helpers remain under `local/scripts/`.

Every visible `.nix` file under `local/` is automatically imported as a module.
A local `default.nix` is another module, not a directory import list. Keep
helper expressions in the owning module's `let` or module `lib` exports as the
contributor guide describes. Put non-Nix sources under `scripts/` or an assets
directory; those names do not exclude a `.nix` file from discovery.

## Reusable module paths

Reusable module paths define public feature selectors. For example,
`modules/home/shells/starship.nix` defines `shells-starship`. Preserve these
paths during asset cleanup. A nearby `<feature>-assets/` directory groups
non-Nix sources for a standalone module without changing its selector.

For reusable modules, adding `default.nix` changes directory aggregation. Read
[the framework contract](../nix-config-framework/README.md#layout-and-selectors)
before moving modules or introducing an aggregate. Target-local discovery has
its own recursive rule described above.

## File names

Use lowercase kebab-case for Nix modules, Markdown topics, shell commands and
JavaScript probe files. Use lowercase snake_case for all Python sources, including executable helpers
and test fixtures. This follows [PEP 8 module naming](https://peps.python.org/pep-0008/#package-and-module-names). Preserve native manifests and recognized entry
names such as `flake.nix`, `default.nix`, `README.md`, `Cargo.toml`, and lockfiles.
An installed command can retain its hyphenated name when its Python source uses
underscores.

Name a maintained source by what it does. `font-element-metrics.cjs` identifies
a browser probe; an old extraction line number does not. Test files use the
runner's `test_*.py` or native `*.test.mts` conventions. Explicit `check_*`
programs are operational probes with arguments and prerequisites, not automatic
pytest suites. Keep fixtures beside the suite that owns them, and give separate
fake behaviors distinct names. Replace extraction ordinals, source line numbers,
and interpolation fragments with a description of the actual behavior. Name
module activation snippets by their action and package lifecycle scripts by
their phase, such as `post-install.sh`. Use names such as
`check_runtime_requirements.py` for Python checks. Retain real version numbers,
numbered decisions, native language conventions, and discovery-test names.

Use each language's real extension. Use `.in` for a source template that is
incomplete before substitution; retain established writer-compatible source
extensions when placeholders already have a dedicated validation path. Follow
[the source and writer conventions](nix-function-conventions.md#source-files-and-language-tooling)
when choosing packaging and validation. Source moves must update sibling imports,
repository-root lookups, lint exceptions and Nix test source sets together.

## Documentation collections

| Location | Reader need |
| --- | --- |
| [Public guide](README.md) and `guide/` | Tutorials and reusable configuration recipes |
| [Operations](operations/README.md) | Setup, deployment, diagnosis and recovery runbooks |
| [Research](research/README.md) | Source-backed investigations and their limits |
| [Reviews](reviews/README.md) | Dated audits and implementation records |
| `agents/` | Task-specific agent workflows |
| `templates/` | Research and task document templates |
| `assets/<topic>/` | Reviewed visual evidence linked from its owning note |

Contributor conventions and security policies stay at their established paths.
The site publishes a curated subset of these files. Collection indexes are
repository navigation; `site/mkdocs.yml` remains the authority for website
navigation. Put new reviewed investigations in `research/<topic>-research.md`
and link them from the research index. Follow [publication policy](publication.md)
for every documentation change.

## Moving a file

Resolve all consumers before moving a file, including Nix source paths, Python
sibling loaders, test fixtures, language-tool exceptions, documentation links,
and external source URLs. Preserve secret identifiers, service names, installed
commands and public feature selectors unless behavior changes are intended.

Verify that every moved source retains its contents and mode apart from reviewed
reference changes. Make new paths visible to Nix's Git source filtering. Run the
owning behavior checks and affected target evaluations; documentation-only moves
need link and formatting checks. A source reorganization does not establish
native runtime behavior or authorize activation.
