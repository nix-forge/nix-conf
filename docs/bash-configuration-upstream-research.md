# Bash configuration upstream research

Research date: 2026-09-01

## Implementation status

The recommendations in this report were implemented on 2026-09-01:

- ble.sh now owns the Bash integration order from an early unattached source
  through a uniquely final attachment;
- Atuin, Carapace, Starship, zoxide, and direnv initialization is generated
  from pinned packages at Nix build time instead of by startup subprocesses;
- fzf uses ble.sh's supported completion, key-binding, and menu modules;
- Atuin owns Ctrl-R in insert and Emacs modes, while vi-normal Ctrl-R remains
  redo; Television's conflicting Bash bindings are disabled without disabling
  Television or `nix-search-tv`;
- Atuin uses ble.sh's native preexec backend without its fallback bash-preexec
  loader, and history filtering was hardened for common credential patterns;
- native Bash history, Readline fallback behavior, Starship SSH context, fzf
  presentation, VS Code automation shells, and Darwin system completions were
  tightened as described below.

The exact generated Bash closures for both configured Darwin and NixOS homes
built successfully. Their generated bashrc files passed Bash syntax checking
and ShellCheck. A clean interactive pseudo-terminal test confirmed the ble.sh
attachment, Atuin preexec backend, vi mode, completion/history/directory/prompt
hooks, and final Ctrl-R ownership.

## Verdict

The base is strong. The configuration uses the current stable Bash patch level,
keeps interactive code behind Home Manager's interactive-shell guard, uses the
right two-stage ble.sh attachment pattern, and has a deliberately small
Starship prompt. The weak point is not Bash itself. It is the order and choice
of integrations around ble.sh.

Three changes should come first:

1. Disable Home Manager's normal fzf Bash integration and load fzf through
   ble.sh's integration modules. Upstream says the normal completion,
   key-binding scripts, and `eval "$(fzf --bash)"` must not be active in a
   ble.sh session.
2. Give `ble-attach` a unique final order. It currently ties Home Manager's
   zoxide integration at order 2000. The generated configuration attaches
   ble.sh first, then initializes zoxide. A live `z` invocation reports the
   resulting zoxide configuration problem because the hook is lost.
3. After those correctness fixes, consider taking direct control of Atuin's
   Bash initialization so Home Manager does not also load `bash-preexec`.
   The current pinned stack adapts those hooks into ble.sh and worked in a
   live test, so this is consolidation and risk reduction rather than a
   currently reproduced failure.

Do not create another NixOS ble.sh module. NixOS has had
`programs.bash.blesh.enable` since release 23.05. Home Manager still lacks a
merged module, and its open replacement PR is stale, draft, and conflicted.
That is the useful upstream contribution.

## What is actually pinned

The root `nixpkgs` input maps to lock node `nixpkgs_3`, commit
[`9fbb54b33e91ee4ca368e35a78e0613c720600b3`](https://github.com/NixOS/nixpkgs/commit/9fbb54b33e91ee4ca368e35a78e0613c720600b3).
Do not use the unrelated lock node literally named `nixpkgs` when auditing this
flake.

Evaluation of the root input and the Darwin and NixOS Home Manager
configurations gives:

| Component | Effective version |
| --- | --- |
| GNU Bash | 5.3 patch 15 |
| ble.sh package | `0.4.0-devel3-unstable-2026-08-12`, commit `95ae551` |
| ble.sh runtime | `0.4.0-devel4+95ae551` |
| bash-completion | 2.18.0 |
| fzf | 0.74.3 |
| Atuin | 18.19.0 |
| direnv / nix-direnv | 2.37.1 / 3.2.0 |
| Starship | 1.26.0 |
| Carapace | 1.7.3 |
| zoxide | 0.10.0 |

Bash 5.3 is the current stable release, and GNU's patch directory ends at
patch 15 as of the research date. The pinned `bashInteractive` is therefore
current. [GNU release directory](https://ftp.gnu.org/gnu/bash/),
[Bash 5.3 patches](https://ftp.gnu.org/gnu/bash/bash-5.3-patches/)

The pinned nixpkgs ble.sh derivation builds a recent upstream commit, runs its
checks, removes build caches from the output, and carries a Nix-specific update
message. There is no reason to fetch ble.sh at shell startup or install it
outside Nix. [Pinned nixpkgs package](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/pkgs/by-name/bl/blesh/package.nix)

## Startup semantics and Home Manager behavior

GNU Bash reads `/etc/profile` and then only the first readable user login file
among `~/.bash_profile`, `~/.bash_login`, and `~/.profile`. An interactive
non-login shell reads `~/.bashrc`. A non-interactive Bash may read the file
named by `BASH_ENV`; a Bash invoked as `sh` follows different POSIX startup
rules. [GNU Bash startup files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)

Home Manager's generated files fit those rules:

- `.bash_profile` sources `.profile`, then `.bashrc`.
- `.profile` loads Home Manager session variables.
- `.bashrc` places `bashrcExtra` before the interactive guard and `initExtra`
  after it.
- `programs.bash.package` defaults to `bashInteractive`.
- `programs.bash.enableCompletion` remains the correct Home Manager option and
  still defaults to true.

These details come from the exact pinned
[Home Manager Bash module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/bash.nix).
The repo correctly puts ble.sh and every other interactive integration in
`initExtra`, not `bashrcExtra`.

The repo's `home.shell` policy also handles Home Manager's newer global shell
integration defaults well. It disables the global switch and enables only the
shells configured in the same Home Manager evaluation. This avoids silently
installing integrations for unused shells. [Pinned Home Manager shell options](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/shell.nix),
[2025 integration-default change](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/news/2025/02/2025-02-07_22-31-45.nix)

## The generated order and its faults

Evaluating `programs.bash.initExtra` for both configured homes produces this
effective order:

| Order | Initialization |
| --- | --- |
| 99 | VS Code Copilot minimal-shell early return |
| 100 tie | ble.sh with `--attach=none`, then bash-completion |
| early | Ghostty integration |
| 200 | normal `fzf --bash` integration |
| normal | Carapace `bash-ble` bridge and Television completion |
| normal | `bash-preexec`, then Atuin |
| after | VTE on Linux, then direnv |
| 1900 | Starship |
| 2000 tie | `ble-attach`, then zoxide |

The Copilot early return is sensible. It skips the expensive interactive stack
and retains only its simple prompt, VS Code integration, and direnv.

The two order ties are brittle. Nix currently happens to put ble.sh before
bash-completion, which is the right direction for ble.sh's "load at the top"
guidance. It also happens to put `ble-attach` before zoxide, which is wrong.
The final attach should use a distinct order later than every prompt, preexec,
directory, and line-editing integration. ble.sh's recommended setup explicitly
sources with `--attach=none` at the top and runs `ble-attach` at the end.
[ble.sh setup](https://github.com/akinomyoga/ble.sh/blob/master/README.md#set-up-bashrc)

### fzf is using the wrong integration

Home Manager emits `eval "$(fzf --bash)"` at order 200. The repo leaves that
integration enabled through `home.shell.enableBashIntegration`. The exact
[pinned Home Manager fzf module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/fzf.nix#L395-L411)
shows the generated command and order.

ble.sh upstream calls out all three normal fzf mechanisms as requiring special
handling: `completion.bash`, `key-bindings.bash`, and `fzf --bash`. It says to
disable those settings in sessions where ble.sh is loaded and instead use
`integration/fzf-completion` and `integration/fzf-key-bindings`. It also
requires bash-completion to load before fzf completion. [ble.sh fzf guidance](https://github.com/akinomyoga/ble.sh/blob/master/README.md#28-fzf-integration),
[complete blesh-contrib instructions](https://github.com/akinomyoga/blesh-contrib/blob/master/integration/fzf.md)

There is one local wrinkle. The repo deliberately gives Ctrl-R to Atuin by
setting fzf's history command to an empty string. ble.sh's fzf key-binding
module binds Ctrl-R unconditionally along with Ctrl-T and Alt-C. Load the fzf
ble module before Atuin so Atuin wins Ctrl-R, or install only the two desired
widgets explicitly. A delayed fzf key-binding import can otherwise reclaim
Ctrl-R after Atuin has initialized. The upstream module's bindings are visible
in [its source](https://github.com/akinomyoga/blesh-contrib/blob/master/integration/fzf-key-bindings.bash).

### Atuin loads a redundant second preexec backend

The pinned Home Manager Atuin module unconditionally sources `bash-preexec`
before evaluating `atuin init bash`. [Pinned Home Manager Atuin integration](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/atuin.nix#L213-L217)

That behavior has fallen behind Atuin. Atuin now recommends ble.sh 0.4 or
newer for Bash, can detect ble.sh when its Bash integration loads, and warns
that bash-preexec has correctness limits around `ignorespace`, subshells,
function definitions, and timing. [Atuin Bash installation](https://github.com/atuinsh/atuin/blob/main/docs/docs/guide/installation.md#bash),
[Atuin shell integration notes](https://github.com/atuinsh/atuin/blob/main/docs/docs/guide/shell-integration.md#bash)

Home Manager has an open Bash history bug involving Atuin, bash-preexec,
direnv, and array-valued `PROMPT_COMMAND`. A 2026 report in that issue
reproduces the same Ghostty, direnv, Starship, and Home Manager combination
used here, and identifies ble.sh as the reliable backend.
[Home Manager issue 5958](https://github.com/nix-community/home-manager/issues/5958)

The current pinned stack did successfully expose Atuin and Starship through
ble.sh's live hooks in a fresh pseudo-terminal, so this is not the first change
to make. A cleaner local target would disable only Atuin's automatic Bash
integration, keep its package, daemon, settings, and other shell integrations,
then evaluate its Bash init after ble.sh is loaded. Prevent Atuin from adding a
fallback bash-preexec copy, and attach ble.sh only after every other integration
has registered. After changing this, replace the shell with `exec bash`;
re-sourcing `.bashrc` cannot cleanly remove old traps and prompt hooks.

### zoxide is initialized after attachment

Home Manager assigns zoxide's Bash init order 2000. The local ble.sh module
also assigns its attach step order 2000. The generated file attaches first,
then evaluates zoxide. [Pinned Home Manager zoxide module](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/programs/zoxide.nix#L41-L45)

zoxide says to put its Bash init at the end of the shell configuration.
[zoxide setup](https://github.com/ajeetdsouza/zoxide/blob/main/README.md#2-setup-zoxide-on-your-shell)
ble.sh ships an integration that advises zoxide's completion and directory
functions when it sees them. [ble.sh zoxide integration](https://github.com/akinomyoga/blesh-contrib/blob/master/integration/zoxide.bash)
The safe local ordering is zoxide near the end, followed by the uniquely-last
`ble-attach`.

### direnv is earlier than later prompt extensions

Home Manager appends the direnv hook, but Starship's explicit order 1900 and
zoxide's order 2000 still place them after it. direnv's own Bash instructions
say its hook should appear after rvm, git-prompt, and other prompt-changing
extensions. [direnv hook instructions](https://github.com/direnv/direnv/blob/master/docs/hook.md)

With ble.sh as the sole preexec backend this is less likely to break history,
but the clean target is Starship, zoxide, direnv, then final `ble-attach`.

## Upstream module status

### NixOS

NixOS already has
[`programs.bash.blesh.enable`](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/programs/bash/blesh.nix).
It simply sources the nixpkgs ble.sh package early in system-wide interactive
Bash initialization. It does not expose package selection, `--attach=none`, a
declarative blerc, or integration ordering.

That module is not a replacement for the repo's Home Manager module. It is
Linux-only, applies system-wide, and cannot express the cross-platform order
needed here. A separate upstream improvement to the NixOS module could add a
robust attach strategy, but creating a second module is unnecessary.

### Home Manager

Home Manager has no ble.sh module at pinned commit `99c9ec6` or current master.
The first attempt, [PR 3238](https://github.com/nix-community/home-manager/pull/3238),
closed without merging. Its successor, [PR 7087](https://github.com/nix-community/home-manager/pull/7087),
is still a draft, has merge conflicts, and has not been updated since
2025-09-21.

An upstream Home Manager module is warranted. Coordinate with PR 7087 instead
of opening an unaware duplicate. A useful version should include:

- `enable`, `package`, and `enableBashIntegration` using Home Manager's global
  shell-integration default;
- an early, uniquely ordered `source ... --attach=none`;
- a uniquely ordered final `ble-attach`;
- a managed blerc or typed options, faces, and imports;
- tests for Starship, zoxide, fzf, Atuin, direnv, and an array-valued
  `PROMPT_COMMAND`;
- documentation that normal fzf Bash integration and redundant bash-preexec
  must be disabled.

The local module should remain until such a module merges and reaches the
pinned Home Manager revision.

## Bash completion option changes

NixOS renamed the system option `programs.bash.enableCompletion` to
`programs.bash.completion.enable`, with a compatibility rename. It defaults to
true and links both legacy and XDG completion directories. [Pinned NixOS completion module](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/programs/bash/bash-completion.nix)

nix-darwin made the same rename, but its new option defaults to false. It links
system completion directories only when enabled. [Pinned nix-darwin Bash module](https://github.com/nix-darwin/nix-darwin/blob/4cff07de74b50e64bdd68cd4e722ab5b6b35ee48/modules/programs/bash/default.nix)

No rename is needed in `modules/home/shells/bash/config.nix`; it sets the Home
Manager option, which is still `programs.bash.enableCompletion`. On NixOS the
system default already exposes package completions. On Darwin, Home Manager
loads its own bash-completion library, but the system completion directories
are not linked. Enable nix-darwin's `programs.bash.completion.enable` if Bash
should discover completions installed by system packages. This also gives
non-Home-Manager users the system completion setup.

## Security and history

The Nix approach is good here. Every evaluated shell fragment comes from a
pinned package or generated Home Manager file. Keep runtime installers and
self-updaters out of `.bashrc`; update the flake lock and review the package
diff instead.

Atuin is the main history database and `auto_sync = true` sends records to the
configured sync service every five minutes. Atuin says sync records are
end-to-end encrypted, but the local encryption key cannot be recovered if
lost. Store that key in the existing secret-management workflow, not in this
repository. [Atuin sync documentation](https://github.com/atuinsh/atuin/blob/main/docs/docs/guide/sync.md)

Atuin's `secrets_filter` defaults to true and rejects recognized AWS, GitHub,
GitLab, Slack, Stripe, npm, and other credential shapes. Upstream calls it a
safety net, not a guarantee. Add `history_filter` and `cwd_filter` patterns for
private project commands and directories. Do not treat a leading space or
`HISTCONTROL=ignorespace` as a security boundary. [Atuin filter settings](https://github.com/atuinsh/atuin/blob/main/docs/docs/configuration/config.md#history_filter),
[built-in secret filter](https://github.com/atuinsh/atuin/blob/main/docs/docs/configuration/config.md#secrets_filter)

The Bash history settings are valid. `ignoreboth` combines `ignorespace` and
`ignoredups`; `erasedups` removes all earlier matching entries before saving a
new one. [GNU Bash history variables](https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html)
The current `historyIgnore` entries are exact patterns, so `ls` is ignored but
`ls -la` is not, and `cd` is ignored but `cd /tmp` is not. Put policy-level
filtering in Atuin if the intention is to exclude command families rather than
only the literal bare commands.
With Atuin providing global deduplicated search, a 100,000-entry in-memory Bash
history and `erasedups` are probably more fallback history than needed. That is
a performance inference, not an upstream requirement. Measure startup and
prompt latency, then consider a smaller Bash fallback such as 10,000 to 20,000
entries and dropping `erasedups`. Keep `histappend`, `cmdhist`, and `lithist`.

Do not put `set -e`, `set -u`, or a global `ERR`/`DEBUG` trap in interactive
startup. Those settings change error and hook behavior for every sourced
integration. Use strict mode inside scripts that are written and tested for it.

The Copilot-only branch sources the path printed by a `code` executable found
through `PATH`. Prefer the Nix-resolved VS Code executable already configured
by the module, capture its output, and source it only when it names a readable
file. This removes an avoidable PATH trust decision and makes a missing shell
integration fail quietly instead of producing a startup error.

## UX and performance choices

Keep these parts:

- Bash 5.3 patch 15 from `bashInteractive`;
- ble.sh for syntax highlighting, autosuggestions, menu completion, multiline
  editing, and its Atuin and zoxide hooks;
- bash-completion for native packaged completions;
- Carapace through its `bash-ble` generator, with Home Manager's normal
  Carapace Bash integration disabled as the repo already does;
- Atuin for searchable, contextual history;
- fzf and fd for file, directory, and completion selection, after moving fzf
  to the ble.sh integration;
- zoxide for ranked directory jumps;
- direnv with nix-direnv for project environments;
- Starship with the existing small format, 250 ms command timeout, and 30 ms
  scan timeout;
- ShellCheck and shfmt, which the repo already installs and runs through its
  development tooling.

Avoid adding another prompt framework, another history manager, or another
full completion framework. The current stack already has one owner for each
job. More frameworks would add prompt hooks, key-binding conflicts, and startup
subprocesses without filling a missing capability.

The exact generated Darwin `.bashrc` passed `bash -n` and built with the pinned
Bash. In a fresh pseudo-terminal with a temporary home and warm Nix store, the
first prompt appeared in roughly 0.5 to 0.7 seconds. Five-run averages for the
runtime init generators were about 42 ms for Carapace, 22 ms for Atuin, 20 ms
for direnv, 18 ms for Starship, 8 ms for zoxide, and 6 ms for fzf, or roughly
116 ms combined. These measurements are directional, not a benchmark of the
user's normal cache and terminal. ble.sh's terminal negotiation and the six
runtime generators are the useful optimization targets; the seven `shopt`
settings are not.

The best final order is:

1. minimal-shell early return;
2. ble.sh source with `--attach=none`, at a unique early order;
3. bash-completion and terminal integration;
4. ble-aware fzf integration;
5. Carapace and static completion files;
6. Atuin initialized against ble.sh, without bash-preexec;
7. Starship, zoxide, and direnv;
8. `ble-attach`, at a unique final order.

## Verification after implementation

Evaluate the generated file, then test a fresh shell rather than re-sourcing an
existing one:

```bash
nix eval --raw \
  .#darwinConfigurations.macbook-pro-m4.config.home-manager.users.ianmh.programs.bash.initExtra

nix eval --raw \
  .#nixosConfigurations.desktop.config.home-manager.users.ianmh.programs.bash.initExtra

exec bash
```

In the fresh shell, verify:

```bash
printf '%s\n' "$BASH_VERSION" "$BLE_VERSION" "$ATUIN_PREEXEC_BACKEND"
atuin doctor
type -a _init_completion _carapace z zi
bind -X | rg 'atuin|fzf'
shopt -p histappend checkwinsize extglob globstar cmdhist checkjobs lithist
```

Test Ctrl-R, Up, Ctrl-T, Alt-C, Tab completion, `z`, `zi`, multiline editing,
direnv enter and leave, command duration and exit status in Atuin, and a prompt
after a failed command. Confirm `ATUIN_PREEXEC_BACKEND` reports ble.sh and that
multiple commands appear in Atuin history. Test Ghostty, VS Code, SSH, tmux,
and the Copilot minimal shell separately.

For startup performance, measure a real pseudo-terminal because ble.sh and
terminal integrations intentionally behave differently without a TTY. Compare
at least 20 fresh interactive starts before and after the integration changes.
The expected gain comes from removing bash-preexec and the normal fzf loader,
not from micro-optimizing the seven Bash `shopt` calls.
