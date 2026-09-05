# Direnv cache location research

Research date: 2026-09-02

## Verdict

Centralize direnv layout storage under one cache root, but give every project
path its own SHA-256-named child directory:

```text
$XDG_CACHE_HOME/direnv/layouts/<sha256-of-$PWD>
```

Do not point every project at the same layout directory. That would make
nix-direnv caches collide. The useful part of centralization is moving cache
files out of source trees and putting them under one disposable root. It does
not mean sharing one cache namespace between projects.

Implement the override once in the Home Manager direnv module through
`programs.direnv.stdlib`. Use the Nix-provided `sha256sum`, not a command that
happens to be available on one host. Create the central root as an owner-only
directory. Keep `.direnv/` in Git ignore files for collaborators and machines
that do not use this personal Home Manager configuration.

## Three different kinds of direnv storage

The word "cache" can blur together files that should not move together.

| Data | Current upstream location | Recommendation |
| --- | --- | --- |
| Project layout and nix-direnv profiles | `$PWD/.direnv` | Move to path-hashed children of `$XDG_CACHE_HOME/direnv/layouts` |
| Approval records created by `direnv allow` | `$XDG_DATA_HOME/direnv/allow` | Leave alone |
| User configuration and extensions | `$XDG_CONFIG_HOME/direnv` | Continue managing through Home Manager |

Direnv 2.37.1 defines `direnv_layout_dir` as an overridable function and
defaults it to `$PWD/.direnv`. The function form matters because `$PWD` can
change while `source_env` or `source_up` evaluates another file.
[Pinned direnv stdlib](https://github.com/direnv/direnv/blob/v2.37.1/stdlib.sh#L110-L119)

Direnv records approvals under `$XDG_DATA_HOME`, not in the layout cache. Its
manual documents `$XDG_DATA_HOME/direnv/allow` and the configuration files
under `$XDG_CONFIG_HOME/direnv`.
[Pinned direnv manual](https://github.com/direnv/direnv/blob/v2.37.1/man/direnv.1.md#files)
Deleting a layout cache must not silently revoke or grant trust, so there is no
reason to relocate the approval database as part of this change.

The XDG specification defines `$XDG_CACHE_HOME` for user-specific,
non-essential data and defaults it to `$HOME/.cache`. It requires XDG base
paths to be absolute. That matches these rebuildable layout files better than
`$XDG_DATA_HOME` or `$XDG_STATE_HOME`.
[XDG Base Directory Specification 0.8](https://specifications.freedesktop.org/basedir/0.8/)

## Why one flat layout is wrong

The repo currently has four `.envrc` files. Each uses `use flake` without an
explicit flake reference. In nix-direnv 3.2.0, that becomes a flake expression
of `.`. nix-direnv derives its final profile name from the flake expression,
not the project path:

```text
flake-profile-<hash-of-.>
```

The implementation then stores that profile, its shell-code `.rc` file, and
flake-input GC roots under the directory returned by `direnv_layout_dir`.
[Pinned nix-direnv flake cache code](https://github.com/nix-community/nix-direnv/blob/3.2.0/direnvrc#L294-L330)

This is visible in the working tree. Both the root and `pkgs` caches contain a
profile named
`flake-profile-a5d5b61aa8a61b7d9d765e1daf971a9a578f1cfa`. They work today
only because one lives under `./.direnv` and the other under
`./pkgs/.direnv`.

If both projects returned the same layout directory, either could import the
other project's cached shell. The timestamp check would not reliably save it:
if the second project's watched files were older than the shared `.rc` file,
nix-direnv would consider the cache current and evaluate that `.rc` as shell
code. This conclusion follows directly from nix-direnv's profile naming,
mtime checks, and `_nix_import_env` call.
[Cache validation and import](https://github.com/nix-community/nix-direnv/blob/3.2.0/direnvrc#L314-L380)

A refresh is also scoped to the whole layout directory. Before installing a
new result, nix-direnv removes the layout's `flake-inputs` directory and every
matching `nix-profile*` and `flake-profile*` entry. A flat global layout would
therefore let one project delete the other projects' GC roots and cached
profiles.
[GC-root cleanup](https://github.com/nix-community/nix-direnv/blob/3.2.0/direnvrc#L208-L228)

nix-direnv uses a PID suffix for its temporary profile, but it does not lock a
shared layout while replacing the final `.rc` and GC roots. Path-hashed child
directories preserve the project isolation provided by today's local
`.direnv` directories. A single flat layout would add cross-project races.
This is an inference from the
[profile update sequence](https://github.com/nix-community/nix-direnv/blob/3.2.0/direnvrc#L359-L380).

## Why a central root with isolated children is a good fit

Direnv's project-hosted cache recipe uses exactly this shape: a central
`~/.cache/direnv/layouts` root and a child name derived from `$PWD`. It calls
the layout content reproducible cache data and says the hash prevents project
name collisions. The page is community-maintained, so the pinned source code
above is the authority for the collision analysis.
[Direnv cache-location recipe](https://github.com/direnv/direnv/wiki/Customizing-cache-location)

For this repo, the change has concrete benefits:

- The four Nix development shells stop leaving `.direnv` directories in the
  root and nested repositories.
- Cache deletion and disk-usage inspection have one obvious root.
- SHA-256 of the full working directory distinguishes the root flake, nested
  repositories, clones, and worktrees even when their basenames match.
- nix-direnv still watches each project's `.envrc`, `flake.nix`, `flake.lock`,
  optional `devshell.toml`, and user direnv configuration. Moving the layout
  does not weaken its normal invalidation.
  [Tracked inputs](https://github.com/nix-community/nix-direnv/blob/3.2.0/direnvrc#L314-L350)

The full path should be hashed as raw input. Flattening `/foo/bar` into a
human-readable name can collide with `/foo-bar`, and putting the whole path in
the directory name can exceed filesystem component limits. A SHA-256 digest is
fixed-length and does not expose checkout paths in directory listings. The
digest prevents accidental cache collisions. It is not a security boundary,
because an approved `.envrc` already executes with the user's permissions.

## Costs and cleanup

Centralization changes cache lifetime. Today, deleting a checkout normally
deletes its `.direnv` and releases its nix-direnv GC roots. With a central
root, moving or deleting a checkout leaves its hashed child behind. Moving a
checkout also causes one fresh evaluation because its absolute path hashes to
a different directory.

`direnv prune` does not clean layout directories. It removes old approval
records.
[Pinned prune implementation](https://github.com/direnv/direnv/blob/v2.37.1/internal/cmd/cmd_prune.go#L9-L74)
This makes occasional deletion of stale children under
`$XDG_CACHE_HOME/direnv/layouts` part of normal cache maintenance. Removing
one or all children is recoverable, but exit the affected development shells
first. The next visit rebuilds each deleted cache, and removing its symlinks
stops protecting those Nix store paths from garbage collection. nix-direnv
documents those links as the mechanism that preserves development
dependencies.
[nix-direnv overview](https://github.com/nix-community/nix-direnv/blob/3.2.0/README.md#nix-direnv)

Do not use `$XDG_RUNTIME_DIR` for this repo. Losing the cache at every logout
or reboot discards nix-direnv's persistent fast path and its GC roots. Also do
not sync the central directory between machines. The cached environment and
Nix store links belong to the local host.

The cache root should not be writable by other users. nix-direnv evaluates the
cached `.rc` as shell code when it restores an environment.
[Environment import](https://github.com/nix-community/nix-direnv/blob/3.2.0/direnvrc#L152-L191)
Owner-only permissions also keep any environment values written by a dev shell
out of other local users' directory listings.

## Repository-specific implementation

`modules/home/dev/direnv.nix` is the right place for the override. Both the
Darwin and NixOS Home Manager configurations include the shared `dev` module,
and `modules/home/xdg/default.nix` already fixes `xdg.cacheHome` to
`$HOME/.cache` on both platforms.

The pinned Home Manager module exposes `programs.direnv.stdlib` and writes it
to `$XDG_CONFIG_HOME/direnv/direnvrc`. It separately installs nix-direnv under
`$XDG_CONFIG_HOME/direnv/lib`, so adding the override does not require editing
any project `.envrc`.
[Pinned Home Manager direnv module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/direnv.nix#L67-L74)
[nix-direnv installation in that module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/direnv.nix#L185-L195)

The implementation should meet these requirements:

1. Override `direnv_layout_dir` through `programs.direnv.stdlib`.
2. Return `${config.xdg.cacheHome}/direnv/layouts/<digest>` where `<digest>`
   is SHA-256 of the current `$PWD` with no trailing newline.
3. Refer to Coreutils' `sha256sum` by its Nix store path so the same function
   works on macOS and Linux.
4. Create the common cache root with mode `0700`, or otherwise verify that only
   its owner can write it.
5. Derive the child from `$PWD` at call time because sourced environment files
   can temporarily change the working directory.
6. Do not set `XDG_CACHE_HOME` globally and do not alter direnv's approval
   database.
7. Keep all existing `.direnv/` ignore rules. They remain correct for portable
   fallback behavior.

After activating the Home Manager generation, reload two different flakes and
verify that `direnv_layout_dir` returns two children of the common root, each
with its own `flake-profile*.rc` and `flake-inputs`. Existing in-project
`.direnv` directories become unused. They can be removed after the new caches
have loaded successfully.
