# Source tree layout research

Reviewed: 2026-09-21. Scope: a portable local layout for Git clones and linked
worktrees on Linux and macOS, with Home Manager, Git, GitHub CLI, and Codex.

## Answer

Keep one user-owned, visible root for long-lived clone checkouts and make its
name a local policy choice. The relevant XDG specifications do not reserve a
directory for source trees. `xdg-user-dirs` is the mechanism that gives a
desktop-facing name to a user folder, and current xdg-user-dirs and Home
Manager include `PROJECTS`; `DEVELOPER` remains a valid extra user-directory
key, not a standardized one.

For this repository, retain `~/Developer` as the canonical root on both
platforms. The active primary checkout and its linked worktrees already use
that path, so moving it would add migration risk without a standards-driven
benefit. Treat `~/Projects` as the general user-project directory on both
platforms.
A greenfield cross-platform setup may instead choose `~/Projects`, but that is
a local convention. Organize persistent clones below the chosen root by forge
owner or trust boundary, then repository name. Do not use XDG data, cache,
state, or config homes for source checkouts.

Keep short-lived Git and Codex-managed worktrees separate from durable clones.
Schedule Git maintenance for selected durable clones. Git shares the object database with linked
worktrees, so registering every linked checkout provides no documented benefit.

## Findings and sources

### XDG scopes and user directories

The [XDG Base Directory Specification, version 0.8](https://specifications.freedesktop.org/basedir/0.8/), published 2021-05-08 and retrieved 2026-09-21, defines base directories for user data, configuration, state, cache, runtime files, and user executables. It does not define a source-project directory or prescribe a layout for version-controlled working trees. Therefore, placing a clone under `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`, or `XDG_CONFIG_HOME` would assign it a meaning that the specification does not give it. This is a source fact followed by a scope inference.

The [xdg-user-dirs project documentation](https://wiki.freedesktop.org/www/Software/xdg-user-dirs/), retrieved 2026-09-21, says that `xdg-user-dirs-update` creates localized well-known directories and writes their locations to `$XDG_CONFIG_HOME/user-dirs.dirs`. It does not prescribe a source-checkout root.

Home Manager's [user-dirs module pinned by this repository](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/misc/xdg/user-dirs.nix), retrieved 2026-09-21, defines `xdg.userDirs.projects` with a default of `~/Projects` and renders it as `XDG_PROJECTS_DIR`. It also accepts arbitrary `xdg.userDirs.extraConfig` keys and emits each as `XDG_<KEY>_DIR`. This makes `DEVELOPER` representable, but it does not make `XDG_DEVELOPER_DIR` a freedesktop standard. The same module writes a read-only `user-dirs.dirs`, can create the configured directories, and, for Home Manager state versions 26.05 and newer, defaults `setSessionVariables` to false. Applications should query `xdg-user-dir` or parse `user-dirs.dirs`, as the module's own option documentation states.

Home Manager's [pinned XDG module source](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/misc/xdg/default.nix), retrieved 2026-09-21, sets the standard XDG environment variables when `xdg.enable = true`; its defaults match the Base Directory Specification's familiar home-relative locations. The implementation does not establish a source-tree root and does not make an XDG user directory mandatory on Darwin.

Apple's [macOS Library directory guidance](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html) puts native application support files and caches under `~/Library`. Home Manager can expose XDG paths to software that supports them on macOS, but those variables do not move every native application's files into XDG directories.

At the start of this work, [`modules/home/xdg/default.nix`](../modules/home/xdg/default.nix) added `DEVELOPER` only on Darwin and repeated `PROJECTS` in `extraConfig` only on Linux. The pinned Home Manager module already defines `projects` on both platforms. The configuration now sets `projects` explicitly and adds `DEVELOPER` on both platforms. The source-code path remains repository policy; neither user directory is an XDG Base Directory location.

### Cloning and Git worktrees

The [GitHub CLI `gh repo clone` manual](https://cli.github.com/manual/gh_repo_clone), retrieved 2026-09-21, accepts an optional destination directory. With no directory it uses Git's normal clone destination. A caller can therefore enforce a chosen root without relying on the current directory, for example by supplying `<root>/<owner>/<repository>`. The CLI chooses its configured Git protocol when the repository argument lacks a scheme. For forks it adds the parent as `upstream` unless `--no-upstream` is used.

The [Git worktree manual](https://git-scm.com/docs/git-worktree), retrieved 2026-09-21, describes linked working trees that share one repository. `git worktree add <path> [<commit-ish>]` creates a linked checkout at the requested path, and `git worktree prune` removes stale administrative information. Git keeps linked-worktree administrative files under the main worktree's `$GIT_DIR/worktrees` directory. The manual therefore supports choosing a sibling or dedicated transient root by passing an explicit path. It does not recommend a universal directory name.

### Proposed checkout layout

Use the same conceptual layout on both platforms. This is a local convention, not a directory structure required by Git or XDG:

```text
~/Developer/
  nix-forge/
    nix-conf/
    ci/
    nix-homelab/
  upstream/
    <owner>/<repository>/
  personal/
    <repository>/
  worktrees/
    <owner>/<repository>/<topic>/   # durable manual worktrees only
```

Keep submodules at the paths declared by their parent repository, such as `nix-conf/pkgs`; they are not standalone replacements for the parent's checkout. Each submodule has its own Git object database, so a host may maintain it separately. For an upstream contribution, keep one checkout under `upstream/<owner>/<repository>`, with the contributor's fork and original repository as separate Git remotes. [GitHub's fork guide](https://docs.github.com/en/pull-requests/how-tos/work-with-forks/fork-a-repo) documents that remote model. Existing clones should move only after their Git worktrees, local changes, submodules, and application references have been reviewed.

### Maintenance

The [Git maintenance manual](https://git-scm.com/docs/git-maintenance), retrieved 2026-09-21, says `git maintenance register` adds the current repository to the user's global `maintenance.repo` list and selects safe background tasks. It also sets `maintenance.strategy=incremental` when that value is unset and disables the repository's foreground auto-maintenance. The incremental schedule enables hourly `commit-graph` and `prefetch`, plus daily `loose-objects` and `incremental-repack`; it disables `gc`.

The same manual says `git maintenance start` performs registration for the current repository and configures a background scheduler for hourly, daily, and weekly tasks. Its automatic scheduler is `systemd-timer` on Linux when available and `launchctl` on macOS. The manual warns that concurrent maintenance runs contend on the object database lock. `maintenance.strategy=incremental` is therefore the documented portable default for registered interactive clones. It is a judgment call whether the prefetch traffic suits a given remote or network.

The Home Manager Git module pinned by this repository at
[`f10b3f2`](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/programs/git.nix), retrieved 2026-09-21, exposes `programs.git.maintenance.enable` and an explicit `repositories` list. Its implementation creates systemd user timers on Linux and launchd agents on Darwin. The repository's existing [Git design note](git-module-research.md) records the intended split: the local home profile owns the absolute maintenance-repository list and the shared Git module sets the incremental strategy. The Home Manager list supplies `maintenance.repo` directly and manages the scheduler. Do not also run `git maintenance start`, which writes its own registration and schedule.

Both [`homes/desktop/local/git.nix`](../homes/desktop/local/git.nix) and [`homes/macbook-pro-m4/local/git.nix`](../homes/macbook-pro-m4/local/git.nix) already enabled that mechanism before this investigation. The desktop list initially covered `nix-conf` and three submodules. This work adds the other inspected, durable nix-forge desktop checkouts. The Mac list remains limited to paths already declared by that host; its live checkout inventory was not inspected here.

### Codex-managed worktrees

The official [Codex worktrees documentation](https://learn.chatgpt.com/docs/environments/git-worktrees), retrieved 2026-09-21, says that managed worktrees live under `$CODEX_HOME/worktrees` by default, use detached HEAD, and are normally lightweight, disposable, and per-chat. Settings > Worktrees configures their location and retention. The same documentation distinguishes permanent worktrees, which are retained and can host multiple chats, from managed worktrees. It also says that worktrees and Git commands remain on the computer or remote development environment that contains the project.

Codex's documented default makes its worktree store separate from the durable clone root. Keep that separation. A permanent worktree belongs beside a durable repository only when its continuing role justifies a stable path.

## Validation and limits

This research reviewed upstream specifications, command manuals, the pinned Home Manager source, and official Codex documentation on 2026-09-21. A read-only Nix evaluation on Linux resolved both host profiles: `XDG_DEVELOPER_DIR` pointed to each host's `Developer` directory, `xdg.userDirs.projects` pointed to `Projects`, and the declared maintenance lists evaluated. It did not build or activate a Home Manager profile, create a clone, start a maintenance scheduler, or create a Codex-managed worktree. No Darwin runtime behavior was tested.

The review did not validate the exact upstream release that first added
`XDG_PROJECTS_DIR`. The note relies on the pinned Home Manager module for the
repository's available `xdg.userDirs.projects` option and makes no broader
version-history claim.

## Implication for this repository

Retain `~/Developer` as the canonical source root for this repository and its
existing linked worktrees. Keep `XDG_PROJECTS_DIR` for general user projects on
both platforms. Keep the host-local maintenance lists limited to durable clones
and submodules. Leave Codex-managed worktrees in their configured worktree
store. Validate the rendered Home Manager output on Linux and Darwin before
activating either machine.
