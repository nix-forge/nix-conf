# Development

The reproducible development environment is provided by the Nix flake:

```sh
direnv allow
nix develop
prek run --all-files
```

The dev partition contains formatters, linters, security scanners, Nix language
tooling, and the repository hooks. Expensive checks such as the full flake
evaluation and native Rust compilation run in CI. Dependency advisory checks
use the current RustSec database through `cargo audit`.

To install or refresh hooks for a clone without entering its development shell,
run `just hooks` from any directory. The command resolves the repository from
its justfile and installs hooks only in that clone; it does not retain another
developer's checkout path.

Direnv loads the pinned Nix shell through `.envrc`; Nix is required. Use
`nix develop` directly when direnv is unavailable. Windows development requires
WSL with Nix and direnv.

Run `javascript-check` inside the shell for TypeScript, Oxlint and formatting.
Nix supplies the compiler, runtime, linter and formatter;
no package-manager install or local dependency directory is needed. Root runtime
helpers belong to the feature-local Cargo workspace. Nix supplies Cargo, rustc,
rustfmt, Clippy, rust-analyzer and advisory tools; no separate Rustup selection
or Python tooling environment is needed for this repository. See the
[Nix-first migration research](research/nix-first-runtime-research.md).

## Rust workstation support

The shared Rust home module installs Rustup and a standalone rust-analyzer. Rustup
selects the compiler, Cargo, rustfmt, Clippy and standard-library sources from each
project's `rust-toolchain.toml`. There is no global `RUST_SRC_PATH` or forced
`RUSTUP_TOOLCHAIN`. The Nix-managed language server has priority over Rustup's LSP
shim and discovers sources through the selected compiler's sysroot.

Project crates, lockfiles, analysis-tool versions and build commands remain owned
by their projects. Existing global Cargo utilities are optional conveniences;
projects can install their own required versions without adding a Nix expression.
This repository's explicit Nix development shell still owns its own tools.

The C/C++ module supplies GNU make, Perl and pkg-config for native build scripts.
GCC is also available for tools that invoke `gcc` explicitly, at lower priority
so Clang retains the default `cc`. The `dev-perf` module supplies Linux
perf without changing kernel sampling permissions. These are workstation
prerequisites, not a Nix build environment for another project.

After activating an updated Home Manager generation, check command ownership:

```sh
type -a rustup cargo rustc rust-analyzer
rustup show
rustup which rustc
```

Use a project's toolchain file to select its compiler. Outside projects, an
optional default can be installed with `rustup default stable`. Miri is an
explicit nightly component; Kani uses its upstream installation procedure and
matching backend. Home activation does not download toolchains or install project
Cargo plugins. Preserve installed toolchains and manually installed tools until
the new generation and the project's commands have been verified; do not use
`rustup self uninstall` as a launcher-cleanup operation.

## Local repository layout

Use `$HOME/Developer` for source checkouts on Linux and macOS. Home Manager
exposes it as `XDG_DEVELOPER_DIR` and leaves `$HOME/Projects` available for
general projects through `XDG_PROJECTS_DIR`. These are user directories;
XDG's config, data, state, and cache directories hold application files.
The [layout research](research/source-tree-layout-research.md) explains the choice.

Place new, durable clones under the remote owner. Keep existing clones at their
current paths until their local changes, linked worktrees, submodules, and app
references have been checked. For a repository you do not already have,
replace `REPOSITORY` below with its GitHub name:

```sh
mkdir -p "$HOME/Developer/nix-forge"
gh repo clone nix-forge/REPOSITORY "$HOME/Developer/nix-forge/REPOSITORY"
```

Use `$HOME/Developer/upstream/<owner>/<repository>` for contributions to another
owner's project, and keep the original repository and your fork as two remotes
in one checkout. Use `$HOME/Developer/personal/<repository>` for personal code.
The host-local Git modules list the durable repositories and submodules that
Home Manager maintains. Add a new path there only after its checkout exists;
Home Manager does not clone repositories during activation.

Keep task checkouts under `$HOME/Worktrees`, with separate `manual`, `codex`,
`claude`, `opencode`, and `t3` directories. Home Manager creates these directories
and adds the Worktrees user-directory bookmark. Permanent clones remain in Developer.

Create a task from a committed base:

```sh
dev-worktree new "$HOME/Developer/personal/example" fix-parser --base main
```

The command prints an absolute path. Ordinary tasks use linked Git worktrees;
a base containing submodules gets an independent clone with separate storage.
Initialize its submodules before evaluating or building. Pending edits and
ignored local files are not copied. Run a terminal agent with
`dev-worktree run PATH -- claude` or the matching agent command to hold a session
lease. This is an optional manual command, not an installed agent skill or
global instruction.

Use `dev-worktree list` or `dev-worktree doctor` for a live inventory. The weekly
report is private state under `$XDG_STATE_HOME/dev-worktree/inventory.json`.
Inventory never deletes files or prunes Git registrations. `dev-worktree move
PATH` previews migration of an ordinary linked task checkout from Developer;
add `--apply --completed` only after closing its editors and agent sessions.
Submodule-containing worktrees and main clones require separate migration.

`dev-worktree remove PATH --retained-ref refs/heads/main` previews removal.
Applying removal also requires `--apply --completed`, a clean checkout, and a
commit retained in the canonical repository. Needed ignored files must be
preserved; `--discard-ignored` explicitly allows their loss. Independent clones
require reviewed archival because their other branches, stashes, and object
storage must survive. The helper never deletes app-managed worktrees.

The shared `programs.dev-worktree.worktreeRoot` option supplies defaults for
native harness settings on both workstation profiles. Each harness module owns
its own setting; the worktree module owns directories, manual commands, and Git
maintenance. It does not export agent instructions, install a worktree skill, or
bundle global `AGENTS.md` or `CLAUDE.md` files.

| Harness | Nix-managed setting | Default location and scope |
| --- | --- | --- |
| Codex | `programs.chatgpt.settings.desktop.git-worktree-root` | `$HOME/Worktrees/codex` for desktop-managed worktrees |
| OpenCode | `programs.opencode.settings.worktree.directory` | `$HOME/Worktrees/opencode` for newly created worktrees |
| T3 Code | `programs.t3code.userSettings.worktreesDirectory` | `$HOME/Worktrees/t3` on the environment host, regardless of its selected provider |
| Claude desktop SSH | `programs.claude-code.settings.worktree.location` | `$HOME/Worktrees/claude` on the SSH host |

Set `programs.dev-worktree.worktreeRoot` in a home's `local/` module to change
these defaults together. Each native assignment uses `lib.mkDefault`, so a
host-specific native setting can override one harness without changing the
others. Settings are applied during Home Manager activation, not continuously
while applications run. Codex's writable TOML is merged by its existing settings
owner; T3's mutable settings merger preserves unrelated provider and connection
preferences.

Native settings have different scopes. Claude's `worktree.location` is read by
Desktop SSH sessions; its CLI, `EnterWorktree`, and isolated subagents continue
to use the repository's `.claude/worktrees` location. See
[Claude's setting reference](https://code.claude.com/docs/en/settings-reference#worktreelocation).
Cursor's documented `.cursor/worktrees.json` controls setup, not a shared
storage root; keep its managed storage app-owned. Other clients can run inside
a manual checkout created by `dev-worktree`. No global creation/removal hooks
or symlinks replace their native lifecycle.

[Codex](https://learn.chatgpt.com/docs/environments/git-worktrees),
[OpenCode](https://opencode.ai/docs/config#worktrees), and T3 manage their own
worktree creation and retention. New location settings do not migrate existing
checkouts. T3 0.1.8 continues recognizing its default managed directory and its
app-owned previous-directory history. Never move, prune, or delete existing
worktrees as part of configuration activation.

Run builds and checks directly with the host's configured compiler parallelism.

## Git maintenance

Home Manager owns the hourly, daily, and weekly maintenance schedules on Linux
and macOS. Each run discovers main clones under Developer, independent manual
task clones, and their initialized submodules, plus the host's explicit
`programs.git.maintenance.repositories` list. It deduplicates shared object
storage and excludes app-managed worktrees. Ordinary linked task worktrees
share their canonical repository's maintenance.

The strategy is incremental. It does not schedule full GC or checkout deletion.
Automatic Git optimization remains available for repositories outside this
layout. Do not also run `git maintenance start` or install a separate scheduler.
Scheduled maintenance and inventory run directly.

```sh
systemctl --user list-timers 'git-maintenance*'
dev-worktree maintain --schedule=daily
```

On macOS, inspect Home Manager's `git-maintenance-*` launchd agents instead.
Source-root discovery stops at each checkout and skips hidden directories and
symlinks. Keep unusual checkout locations in the host's explicit repository
list. No repository is cloned during Home Manager activation.

## JavaScript and TypeScript

Prefer TypeScript for maintained programs when the consuming runtime or build
system supports it. Running TypeScript does not check its types. Keep a compiler
check in the owning repository or package. Node commands use erasable syntax and
explicit `.mts` or `.cts` extensions; the declared Node 24 and 26 runtimes execute
these sources directly. Browser application sources still compile into JavaScript.

The JavaScript inventory covers this repository and all initialized submodules.
The framework, secret-management, and homelab repositories have no independently
maintained JavaScript source programs. Their application integrations consume
package outputs, generated preferences, and short browser expressions.

| Source                                                                                           | Choice and check                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Package module smoke checks, manifest scripts, Aurral native smoke check                         | TypeScript `.mts`, checked by the package repository's JavaScript quality check. Standalone packages retain identical local copies of the module smoke helper and resolve dependencies from the caller's directory. |
| Feishin lifecycle and Samsung power-state regression tests                                       | TypeScript `.mts`, included in the package repository's compiler and lint checks. Their package checks still execute the actual patched upstream implementation.                                                    |
| ReactFlux authentication, session store, media policy, image gallery and image integration tests | TypeScript and TSX. Vite compiles application sources. The package checks these sources against its locked React, Vite, parser, and nanostores declarations before running image tests.                             |
| Feishin and Stirling `.js.in` fragments, upstream patch hunks                                    | Keep exact upstream JavaScript. Partial fragments are not compilation units. Source anchors, assembled-program parsing, and package behavior checks validate them.                                                  |

Root and package `javascript-check` commands run compiler, lint and formatting
checks for surviving maintained JavaScript and TypeScript. Compiler discovery
uses `scripts/typescript/projects.json`; native Nix validates strict options and
explicit source coverage in `flake/dev/javascript-tools.nix`. Keep compiler manifests, source
selection and runtime callers aligned when adding programs. The root excludes
subprojects, whose static tooling is owned independently.

See [Node's TypeScript execution rules](https://nodejs.org/api/typescript.html)
and [TypeScript's JavaScript checking option](https://www.typescriptlang.org/tsconfig/checkJs.html).

## CI runtime and cache ownership

The early Rust job owns workspace formatting, compilation and Clippy before
other native work. Local hooks and full `lintChecks` remain available. Hosted lint retains its
other language, formatting and publication checks; library tests remain separate.

`Seed reviewed static CI caches` warms only the reviewed Linux `ciRust` and
`ci` tool environments after relevant default-branch dependency changes or an
explicit default-branch dispatch. It retains a Nix profile through post-job GC.
Rust and lint consumers use matching workload keys and read-only mode. Source
changes still require their exact Nix outputs; an older dependency restore does
not make a changed check pass. Cache post-action logs record actual transfer and
save outcomes, while summaries report policy, matched keys, timing and retained
closure size. No new cache account or publication credential is required.

The native/package audit stores remain outside automatic warming. Archive only
closures whose contents can be shared with contributors; a GitHub store cache
includes the whole store, including dependencies. Native artifacts, credentials,
private data and redistribution-restricted packages require their own review.
The shared native runner supports small bounded evaluation batches. Current
batch failures fall back to isolated current evaluation; unknown or timed-out
historical entries rebuild. Reuse also requires the latest owning GitHub Actions
`Repository tests` aggregate to have succeeded on the exact base commit; missing,
pending or failed evidence rebuilds current checks. Do not replace conservative fallback with source-path
heuristics or treat submission as completed validation.
See the [runtime audit](research/ci-runtime-cache-audit-research.md) for the measured
baseline and benchmark acceptance criteria. Compare cold and restored runs of the
same source before claiming a cache speedup.
