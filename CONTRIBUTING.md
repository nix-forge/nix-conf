# Working on nix-conf

This repository selects and configures workstation features. Start with the
affected host or home profile, then follow its selected modules to the behavior
being changed. The [glossary](GLOSSARY.md) distinguishes those concepts.

## Repository boundaries

The root repository owns workstation configuration and integration. Its
submodules are separate repositories with their own checks and release history:

| Change | Owning repository |
| --- | --- |
| Host policy, home profiles, feature selection, integration | This repository |
| Package recipes and source updates | `pkgs/`, the nixpkgs-personal repository |
| Target discovery and module composition | `nix-config-framework/` |
| Secret-management implementation | `nix-seal/` |
| Reusable homelab service modules | `nix-homelab/` |

Read the owning repository's instructions before editing it. Keep its changes
and validation separate from the root's gitlink update. A root diff shows only
the submodule revision, not the code inside it. Check `git status` in each
affected repository before staging; existing staged and unstaged work may belong
to another task.

## Configuration conventions

Use the [layout and naming guide](docs/layout.md) when adding or moving files.
It records source ownership, naming rules, and the consumers a move must update.

- Select reusable features in the target's `default.nix`. Put target-specific
  settings and configuration assets in its `local/` tree. That tree auto-imports
  Nix files, so each Nix file must be a module. Export target-specific helper
  functions through the module's `lib` option. Reserve `lib/` for algorithmic
  or mathematical helpers and functions used by multiple production callers.
  Keep one-off functions in the caller's `let`, or beside the feature when
  several modules in that feature need them.
  Group related local modules in domain directories such as `local/network/`
  and `local/security/`, with short filenames inside them. Local directories
  remain recursively imported: `local/<domain>/default.nix` is another module,
  not an import list. Keep runtime unit, option, and secret names stable when
  moving source files.
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
- Follow the [Nix function conventions](docs/nix-function-conventions.md) when
  rendering templates or packaging Bash and Python helpers. Package local
  commands with Nix and install them through the owning module instead of
  placing executable files in `~/.local/bin`.

## Waiting and readiness

Do not busy-wait for state changes. Use blocking process, descriptor, filesystem,
D-Bus, or lifecycle notifications when the producer supports them. Subscribe
before taking the initial snapshot, recheck state after notifications, and use
one overall deadline. Keep cancellation and resource cleanup with the owner.

Let the service manager own restarts. Ordering after a process start does not
prove application readiness; prefer the application's native readiness signal.
For a protocol without notifications, document why a bounded retry is necessary,
use positive backoff, honor server retry hints, and retry only safe operations.
Never replace a notification wait with a zero-timeout status loop. On Python 3.14,
`Popen.wait(timeout=...)` polls internally; Linux process supervision should use
pidfds or an asynchronous child observer instead.

Prefer native NixOS, Home Manager and nix-darwin options, Nix format generators,
package combinators and service-manager directives over custom scripts. Nix
must not inspect mutable runtime state or materialize plaintext secrets in the
store. Use Swift for macOS-specific runtime code when direct access to Apple
frameworks simplifies the implementation. Use Rust for other project-owned
runtime algorithms, including shared and cross-platform helpers. Preserve
existing contracts when migrating helpers. Keep required upstream configuration
languages, exact patch fragments and minimal activation/build shell glue. The
root Cargo workspace owns feature-local Rust helpers; submodule workspaces remain
independent. Use the pinned Nix shell rather than a separate Rustup toolchain.
See [the migration research](docs/research/nix-first-runtime-research.md).

Keep standalone programs in language source files, including package checks and
VM drivers. Keep small shell glue inline with the checked shell writers. Use the
owning repository's declared language tooling and the Nix helper appropriate to
its lifecycle. See the
[source and writer conventions](docs/nix-function-conventions.md#source-files-and-language-tooling)
for file extensions, writers, rendering, and import lookup when extracting code.

Development dependencies belong in the Nix shell, loaded with direnv or
`nix develop`. Do not install repository tooling with npm, pnpm, Bun, pip or uv,
or create local dependency directories or virtual environments. The root Cargo workspace and lockfile declare runtime dependencies. Application
package recipes retain their own upstream build dependencies inside Nix builds.

## Validation

See the [testing guide](docs/testing.md) for test layers, commands, fixture
conventions, and the framework decision.

### Automated testing policy

Automated tests cover functions in `lib/` through the pinned `nix-unit` runner.
Use named expressions, expected values and specific expected errors. Do not add
project-owned behavior, configuration snapshot, generated-output, integration,
VM or non-Rust fuzz suites. The nix-seal repository additionally retains Rust tests.

Keep formatting, lint, syntax, type, schema, documentation and security checks.
Put genuine invalid-setting invariants in the owning module's `assertions` block;
do not assert a selected host value merely to freeze configuration. Preserve
production input validation, activation safeguards and upstream package test defaults.
Do not move implementation into `lib/` simply to retain an excluded test suite.

Run `just test` for library functions and `just check` for the retained checks.
Definitions live in `flake/dev/lib-tests.nix`, `flake/dev/checks.nix`,
`flake/dev/formatter.nix` and `flake/dev/git-hooks.nix`. Each subproject owns its
suite and static tooling. Use `nix develop` for pinned tools. Add new source files
to Git's source view deliberately before claiming that a flake evaluation includes them.

Run focused checks first and the retained checks affected by the change. Report
which platforms ran and distinguish evaluation, build and activation. Static and
library checks do not establish runtime or recovery behavior. Follow the desktop
build-placement rule in [AGENTS.md](AGENTS.md); deployment is a separate action.

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
builds, and remote builders can still build packages selected
by the configuration. Their upstream terms remain applicable. The exclusions do
not mean every private build is prohibited, or that private use is automatically
permitted. See the [package licensing policy](pkgs/docs/package-licensing.md).

Hosted builds must respect package licensing exclusions. Cache download settings
do not publish outputs; review permissions separately before adding cache uploads
or release artifacts.

## Work records and review

Use the [workflow guide](docs/agents/workflows.md) to choose a skill and the
[tracker guide](docs/agents/issue-tracker.md) to find its requirements. Routine
work can use the user's request directly; it does not need an issue or ADR.

Before committing, inspect the staged patch and include only the intended task's
changes. For a review, name the exact base, repositories, and source of acceptance
criteria. Report standards findings separately from requirements findings.
Describe what changed, how it was verified, and any remaining runtime checks.

Report vulnerabilities through [SECURITY.md](SECURITY.md).
