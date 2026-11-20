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
| `lib/tests/` | Library cases and their fixtures |
| `flake/public-demo/` | Disposable public practice configuration |
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

Keep runtime sources with their owning feature. Music bootstrap and
integration crates live under `local/homelab/music/`. Actual's runtime code
lives under `local/homelab/actual/protocols/`, and homelab credential helpers
live under `local/homelab/credentials/`. Place templates and other assets
beside the code that reads them.

The framework auto-imports visible Nix files recursively under a target's
`local/`, including `default.nix`. Use module options for shared module
settings and explicit imports for pure helpers. A feature-private Nix
expression under a discovered tree can use a dot-prefixed filename, as
`modules/nixos/virtualisation/.libvirt-artifacts.nix` does. Keep that file in
Git and import it explicitly. A visible `assets/` or `scripts/` directory
still participates in discovery.

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

Use lowercase kebab-case for Nix modules, Markdown topics, shell commands
and standalone JavaScript filenames. Use lower camel case for private Nix
bindings and include a unit in the name where it affects interpretation,
such as `memoryMiB`. Use snake_case for private Rust bindings and modules
and for Python sources in repositories that use Python. Keep recognized
toolchain filenames and existing public executable names.

Name a source for its operation or the data it owns. Use names such as
`backup_policy` and `source_manifest` where values cross phases. Name
template variables for their purpose and escaping contract. Preserve real
version numbers, native naming conventions and discovery fixture names.

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
