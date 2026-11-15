# Jujutsu module research

## Recommendation

Add a small shared Home Manager module at `modules/home/dev/jj.nix` and keep
identity, signing keys, trusted signers, and any work-only behavior in each
host's `local` directory. Jujutsu is deliberately Git-compatible, but it does
not reproduce every Git feature. The module should make the normal Git-backed
workflow pleasant without hiding those limits.

The pinned Nixpkgs package is Jujutsu 0.44.0. It supports Linux and Darwin and
installs its Bash, Fish, Nushell, and Zsh completions. See the pinned
[Nixpkgs derivation](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/ju/jujutsu/package.nix).

Use Home Manager's `programs.jujutsu` rather than writing
`~/.config/jj/config.toml` directly. The pinned module creates the TOML config
with Nix's TOML generator, installs the selected package, and selects the XDG
location on Darwin for jj 0.29 and later. It also has an optional Emacs ediff
integration. The shared module should set `ediff = false` explicitly because
this configuration uses Neovim, and a merge tool should never appear merely
because another editor happens to be enabled. See the pinned [Home Manager
module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/jujutsu.nix).

The existing Git module already configures Delta. Turn on its explicit
`programs.delta.enableJujutsuIntegration` option in the jj module. Home Manager
then supplies Delta as jj's pager, selects jj's `:git` formatter, and accepts
Delta's normal diff exit codes. This matches jj's own Delta guidance. Do not
also hand-write `ui.pager`, `ui.diff-formatter`, or `merge-tools.delta`; two
owners for the same TOML keys are needless configuration debt. See the pinned
[Delta module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/delta.nix)
and [jj pager documentation](https://jj-vcs.github.io/jj/latest/config/#pager).

## Shared settings

The shared module should be conservative. jj has good defaults, and repeating
them makes future upgrades harder. The following are useful explicit choices:

```nix
{
  programs.jujutsu = {
    enable = true;
    package = pkgs.jujutsu;
    ediff = false;
    settings = {
      ui = {
        color = "auto";
        conflict-marker-style = "git";
      };
      merge.hunk-level = "line";
      working-copy.eol-conversion = "input";
      git.private-commits = "description('wip:*') | description('private:*')";
    };
  };

  programs.delta.enableJujutsuIntegration = true;
}
```

Set `ui.editor` only when `home.sessionVariables.EDITOR` is present, using the
same conditional pattern as the Git module. jj otherwise resolves its editor
in this order: `JJ_EDITOR`, `ui.editor`, `VISUAL`, `EDITOR`, then Nano. That
keeps a per-shell or one-off `JJ_EDITOR` override useful. [jj editor
documentation](https://jj-vcs.github.io/jj/latest/config/#editor)

`ui.color = "auto"` preserves useful terminal output without leaking ANSI
escapes into pipes. Delta uses Git-style diff input, so its Home Manager
integration's `ui.diff-formatter = ":git"` is the correct companion setting.
jj's default color-words formatter is otherwise a fine fallback when Delta is
disabled. [jj diff and external formatter
documentation](https://jj-vcs.github.io/jj/latest/config/#diff-format)

Use `ui.conflict-marker-style = "git"` as the shared setting. It gives editors,
formatters, and Git-oriented tools the diff3 markers they recognize. jj falls
back to its snapshot style for a conflict with more than two sides, where a
Git-style marker cannot represent the state. Its native `diff` style is more
expressive, but interoperability wins for a cross-platform default. [jj
conflict documentation](https://jj-vcs.github.io/jj/latest/conflicts/#alternative-conflict-marker-styles)

Keep `merge.hunk-level = "line"`, jj's default. Word-level merge hunks make
some conflicts smaller but change resolution behavior across every repository.
Use it per repository only after the team has tried it. Leave
`merge.same-change = "accept"` at its default, which resolves identical edits
as Git and Mercurial do. [jj merge settings](https://jj-vcs.github.io/jj/latest/config/#merge-settings)

`working-copy.eol-conversion = "input"` matches the Git module's
`core.autocrlf = input` policy. It accepts CRLF on input and stores LF, but
does not force CRLF on checkout. This is the least surprising portable setting
for Linux and macOS. [jj EOL conversion
documentation](https://jj-vcs.github.io/jj/latest/config/#eol-conversion-setting)

The `git.private-commits` revset is a useful last line of defense. A change
whose description starts `wip:` or `private:` and any descendant will not push.
It deliberately does not try to infer secrets from file names. A user still
needs to remove a secret from history if it has entered a change. The setting
does not treat an already-pushed change as private. [jj private commit
documentation](https://jj-vcs.github.io/jj/latest/config/#set-of-private-commits)

Do not set `git.colocate` globally. jj defaults to colocated repositories,
which puts `.git` next to `.jj` and makes normal build tools, IDEs, Git
credential helpers, hooks triggered by Git commands, and forge CLIs work in the
same checkout. For unusually large repositories or workflows that should never
mix Git writes with jj writes, choose `jj git clone --no-colocate` or set
`git.colocate = false` in that repository. [jj Git compatibility
documentation](https://jj-vcs.github.io/jj/latest/git-compatibility/#colocated-jujutsugit-workspaces)

## Local identity and signing

Identity belongs in `homes/desktop/local/jj.nix` and
`homes/macbook-pro-m4/local/jj.nix`, sourced from the same protected local
identity material as Git. Do not put a name, email address, public-key path,
allowed-signers path, or work-email condition in the reusable module.

```nix
{ config, lib, pkgs, ... }:
{
  programs.jujutsu.settings = {
    user = {
      name = "...";
      email = "...";
    };
    signing = {
      behavior = "drop";
      backend = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      backends.ssh = {
        program = lib.getExe' pkgs.openssh "ssh-keygen";
        allowed-signers = config.nixSeal.secrets.jj-allowedSigners.path;
      };
    };
    git.sign-on-push = true;
  };
}
```

This is a model, not an instruction to create a new secret name. Follow the
existing `hasSecret` guard used by the local Git module, and reuse its allowed
signers file when its format and policy suit jj. A local config can omit
`allowed-signers` if signature verification is not wanted.

SSH signing is the natural match for this repository's Git signing setup. jj
uses `ssh-keygen`, accepts a public key or public-key path, and requires an
allowed-signers file to verify signatures. Pinning the executable to
`pkgs.openssh` avoids accidentally selecting an older system OpenSSH on either
platform. [jj SSH signing
documentation](https://jj-vcs.github.io/jj/latest/config/#ssh-signing)

For a hardware-backed or otherwise interactive signer, use
`signing.behavior = "drop"` with `git.sign-on-push = true`. jj signs mutable
unsigned commits in one batch at push time. This avoids prompts and signing
work on every amend or rebase. For a non-interactive software key, `behavior =
"own"` is a reasonable local opt-in. Never use `force`: it signs modified
commits even when somebody else authored them. [jj automatic signing
documentation](https://jj-vcs.github.io/jj/latest/config/#automatically-signing-commits)

Leave `ui.show-cryptographic-signatures` off globally. jj disables signature
verification and display by default because it costs time on medium and large
logs. Enable it in a local or repository config only where reviewing signatures
is worth that cost. [jj signature verification
documentation](https://jj-vcs.github.io/jj/latest/config/#commit-signature-verification)

## Git interoperability

jj invokes Git for remote operations, so it inherits the existing Git package,
SSH configuration, credential helpers, and `gh`/`glab` authentication path.
Configure the jj module after the Git module, but do not duplicate Git's
credential settings in jj. jj reads Git remote configuration and
`core.excludesFile`, and respects `.gitignore`; it does not implement Git
hooks, Git LFS, submodules, partial clones, standard worktrees, or
`.gitattributes`. That distinction needs to be visible in the module comments
and user documentation. [jj Git compatibility matrix](https://jj-vcs.github.io/jj/latest/git-compatibility/#supported-features)

Colocation automatically imports and exports Git state on every jj command. It
is safe to read with Git, but jj's guidance is to make jj the primary writer.
Mutating Git commands can leave Git detached, background Git fetches from an
IDE can make branch state confusing, and Git tools do not understand jj's
conflicted tree encoding. `jj undo` and `jj op restore` can recover Git changes
recorded by an import operation. [jj colocated-workspace behavior](https://jj-vcs.github.io/jj/latest/git-compatibility/#colocated-jujutsugit-workspaces)

Do not set `remotes.origin.auto-track-bookmarks = "*"` globally. On a shared
remote it tracks everybody's bookmarks and makes a later `jj git push` more
surprising. Keep jj's selective default. If a fork has a stable policy, set it
in that repository, for example all bookmarks for a personal `origin` and only
`main` for `upstream`. [jj bookmark tracking
documentation](https://jj-vcs.github.io/jj/latest/config/#automatic-tracking-of-bookmarks)

Likewise, leave `git.fetch`, `git.push`, remote refspecs, and the generated
bookmark prefix unset globally. They describe a repository's forge topology,
not a machine-wide policy. Clone-time configuration already discovers a trunk
bookmark. A global `trunk()` alias or a `main@origin` log revset would break
repositories that use `master`, release branches, or a different remote.

Keep jj's default immutable heads. It protects trunk, tags, and untracked
remote bookmarks. Add project-specific release or deployment bookmarks in the
repository's config with `builtin_immutable_heads()` as the base. Never replace
the alias with a narrow custom expression, which would weaken jj's protection.
[jj immutable commits documentation](https://jj-vcs.github.io/jj/latest/config/#set-of-immutable-commits)

## Revsets, templates, and aliases

The shared config should not change `revsets.log`, `revsets.short-prefixes`,
or the log template. jj already shows the working copy, nearby mutable history,
and trunk. Changing `revsets.log` also changes the default short-prefix scope,
which can make command-line IDs longer in a large repository. Templates and
revsets are powerful, but every global customization becomes part of the muscle
memory of every repository. [jj log revset
documentation](https://jj-vcs.github.io/jj/latest/config/#default-revisions)

Add only short, direct aliases if they solve a demonstrated daily problem. A
good pattern uses an argument array and a completion description:

```nix
programs.jujutsu.settings.aliases = {
  st = {
    definition = [ "status" ];
    doc = "Show working-copy status";
  };
};
```

Avoid aliases using `util exec`, shell fragments, or network commands in the
shared module. They execute arbitrary commands on the user's machine, can make
the operation log harder to reason about, and have no place in a declarative
default. [jj alias safety warning](https://jj-vcs.github.io/jj/latest/config/#aliases)

Use conditional `conf.d` TOML only for user-owned, location-based variants
that do not contain secrets. jj loads the user config at the XDG path on both
Linux and macOS, and supports a directory of TOML files in lexical order.
`--when.repositories` can select a path prefix. Home Manager owns one generated
`config.toml`, so host-local Nix modules remain the cleaner way to express this
repository's secret-aware policies. [jj user config and conditional variables
documentation](https://jj-vcs.github.io/jj/latest/config/#user-config-files)

## Snapshots, filesystem monitoring, and performance

jj snapshots the working copy at the start of almost every jj command. New
non-ignored files are tracked by default, and the default maximum size for a
new snapshot file is 1 MiB. Keep that default. It catches accidental build
outputs and downloads without changing normal source-control behavior. Use
`.gitignore` plus `jj file untrack` for an accidental addition, not a broad
machine-wide `snapshot.auto-track` exception. [jj working-copy
documentation](https://jj-vcs.github.io/jj/latest/working-copy/)

Leave `snapshot.auto-update-stale` disabled. Explicit stale-workspace recovery
makes cross-workspace updates visible. A developer who routinely uses several
jj workspaces can enable it locally after deciding that automatic working-copy
rewrites fit their workflow. [jj stale-working-copy
documentation](https://jj-vcs.github.io/jj/latest/working-copy/#stale-working-copy)

Do not install or enable Watchman on every machine. It helps large working
copies avoid full rescans, but uses one inotify watch per file and can worsen
behavior when the watch limit is too low. Enable `fsmonitor.backend =
"watchman"` and its snapshot trigger only in a local profile for repositories
where measurements justify it. Verify with `jj debug watchman status`. This
keeps the shared Linux and macOS configuration free of an always-running
watcher. [jj filesystem-monitor documentation](https://jj-vcs.github.io/jj/latest/config/#filesystem-monitor)

Colocation can slow jj in repositories with many refs because it imports Git
state on each command. First run `jj util gc` in the affected repository. It
packs Git refs and is the upstream mitigation. If the problem remains, use a
non-colocated jj workspace rather than putting global performance flags into
the module. [jj colocation performance guidance](https://jj-vcs.github.io/jj/latest/git-compatibility/#colocated-jujutsugit-workspaces)

## Validation

After implementation, evaluate both Home Manager configurations and inspect the
generated TOML. On an activated host, these checks cover the important wiring:

```sh
jj config path --user
jj config list --include-defaults
jj --config ui.color=never status
jj git clone https://github.com/octocat/Hello-World /tmp/jj-smoke
cd /tmp/jj-smoke
jj status
git status
jj git colocation status
```

Use a throwaway clone. It verifies that jj can find the pinned Git executable,
that Git credentials remain Git-owned, that jj and Git can inspect a colocated
workspace, and that no user identity or signing material was committed to the
repository.
