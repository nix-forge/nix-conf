# Development

The reproducible development environment is provided by the Nix flake:

```sh
direnv allow
nix develop
prek run --all-files
```

The dev partition contains formatters, linters, security scanners, Nix language
tooling, and the repository hooks. Expensive checks such as the full flake
evaluation and Rust audit/test suites run in pre-push hooks or CI.

To install or refresh hooks for a clone without entering its development shell,
run `just hooks` from any directory. The command resolves the repository from
its justfile and installs hooks only in that clone; it does not retain another
developer's checkout path.

On Windows, direnv is supported through WSL or Git Bash. If Nix is absent,
`.envrc` loads only a small project-root/path environment so shell startup does
not fail; it does not provide the reproducible tools above. Native PowerShell
direnv is outside the supported scope.

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
and `claude` directories. Home Manager creates these directories and adds the
Worktrees user-directory bookmark. Permanent clones remain in Developer.

Create a task from a committed base:

```sh
dev-worktree new "$HOME/Developer/personal/example" fix-parser --base main
```

The command prints an absolute path. Ordinary tasks use linked Git worktrees;
a base containing submodules gets an independent clone with separate storage.
Initialize its submodules before evaluating or building. Pending edits and
ignored local files are not copied. Run a terminal agent with
`dev-worktree run PATH -- claude` or the matching agent command to hold a session
lease. Global instructions in Codex, Claude Code, and OpenCode use this policy.

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

Codex's native worktree root is set to `$HOME/Worktrees/codex` through an atomic
merge that preserves its writable settings. Let the app manage retention and
handoff. Existing managed checkouts are not relocated by this setting. For
Claude desktop, select `$HOME/Worktrees/claude` in Settings > Claude Code >
Worktree location on the host where it runs. No declarative key for that native
setting has been verified. Cursor retains its own exclusive managed root.

The reusable worktree module owns `programs.dev-worktree` paths, commands,
maintenance, and the shared instruction text. Each terminal client's module
adds that text through its own Home Manager `context` option. The Codex desktop
module owns native settings through `programs.chatgpt.settings`; the workspace
root and Stylix appearance are merged before one activation step updates the
writable TOML file. Unconfigured trust and session preferences remain app-owned.
Changing `programs.dev-worktree.worktreeRoot` updates the default Codex root.
Host-specific native preferences can be set in the home's `local/` modules:

```nix
programs.chatgpt.settings.desktop.git-worktree-root = "/absolute/tasks/codex";
```

Settings are reapplied during Home Manager activation, rather than continuously
enforced while the app runs. Claude Code's CLI has no verified worktree-root
setting; use `dev-worktree` and launch it inside the resulting checkout.

Short bounded desktop checks can use `workstation-task --feedback`; full builds
and acceptance suites use the default bulk lane. See
[desktop memory management](operations/desktop-memory-management.md) for limits,
failure behavior and standalone runner installation. Task lifetime helpers do
not replace workload scheduling.

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
On desktop, scheduled maintenance and inventory use `workstation-task`.

```sh
systemctl --user list-timers 'git-maintenance*'
workstation-task dev-worktree maintain --schedule=daily
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
| Root browser fixtures, DOM observer, disposable VS Code extensions, Electron startup probe       | TypeScript `.cts` or `.ts`, checked by the strict root compiler. Node type erasure produces JavaScript before WebDriver, CDP, VS Code, or Electron receives the source.                                             |
| Jellyfin caption regression test                                                                 | TypeScript `.cts` with an explicit settings contract at its VM boundary. The patch check uses the declared Node 24 interpreter.                                                                                     |
| Package module smoke checks, manifest scripts, Aurral native smoke check                         | TypeScript `.mts`, checked by the package repository's JavaScript quality check. Standalone packages retain identical local copies of the module smoke helper and resolve dependencies from the caller's directory. |
| Feishin lifecycle and Samsung power-state regression tests                                       | TypeScript `.mts`, included in the package repository's compiler and lint checks. Their package checks still execute the actual patched upstream implementation.                                                    |
| ReactFlux authentication, session store, media policy, image gallery and image integration tests | TypeScript and TSX. Vite compiles application sources. The package checks these sources against its locked React, Vite, parser, and nanostores declarations before running image tests.                             |
| Existing Spotify extension, homelab helpers, Feishin helpers, T3 runtime check and root probes   | Check every standalone compiler project through the package repository command as well as its package-specific build.                                                                                               |
| Feishin and Stirling `.js.in` fragments, upstream patch hunks                                    | Keep exact upstream JavaScript. Partial fragments are not compilation units. Source anchors, assembled-program parsing, and package behavior checks validate them.                                                  |
| T3 CommonJS loader fixtures, preference assignments and short HTML or browser expressions        | Keep JavaScript where the fixture tests CommonJS loading itself or the application requires JavaScript text. These small expressions do not justify a compiler pipeline.                                            |

Root `npm run check` includes all maintained root JavaScript and TypeScript tests
and the caption regression source. Its test command requires
`METABRAINZ_EXTENSION` as described in [the testing guide](testing.md).
The package repository's `npm run check` covers maintained Node helpers and tests;
ReactFlux's image test is checked inside its package build, where its real
application dependencies are available. Substantial Electron and CDP renderer
programs also live in TypeScript and emit JavaScript for their consumers.
Narrow local declarations for browser,
VS Code, Electron, and nanostores host contracts support standalone checking;
they do not replace integration checks against those applications.

New browser TypeScript under `tests/` automatically enters the root compiler
project. Use the shared source adapter in `tests/typescript/source.mts` and
`tests/typescript_sources.py` when a consumer requires JavaScript text. The adapter
erases types without introducing CommonJS or ES module compiler boilerplate.
JavaScript remains included in the compiler project for future intentional fixtures. New package script `.mts` files enter the package compiler project and
Nix source set. Keep type-check, lint, formatter, Nix source selection, and runtime
callers aligned when adding other programs. Never bypass an incompatible runtime
by renaming a source file without updating its consumers.

See [Node's TypeScript execution rules](https://nodejs.org/api/typescript.html)
and [TypeScript's JavaScript checking option](https://www.typescriptlang.org/tsconfig/checkJs.html).
