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
The [layout research](source-tree-layout-research.md) explains the choice.

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

Keep manually created, long-lived worktrees under
`$HOME/Developer/worktrees/<owner>/<repository>/<topic>`. Remove one with
`git worktree remove` when its work is finished. Let Codex manage its own task
worktrees through the app. Do not move or prune those directories behind the
app's back. A worktree of this repository needs its own
`git submodule update --init --recursive` before full flake evaluation.
