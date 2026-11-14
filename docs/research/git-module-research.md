# Git module research and design

## Decision

Keep one portable Home Manager Git policy in `modules/home/dev/git.nix`. Keep
identity, signing-key selection, trusted signer lists, work-only credentials,
and repository paths in each `homes/*/local/git.nix`. The shared module should
make ordinary commands predictable. It should not decide which identities can
sign, which repositories are trusted, or how a particular employer wants its
history rewritten.

Home Manager is a good fit for this split. Its `settings` option writes the
XDG Git config, `includes` supports both a path and a Git conditional include,
and its signing options generate `user.signingKey`, `commit.gpgSign`,
`tag.gpgSign`, `gpg.format`, and the correct signer program. Its maintenance
option creates systemd user timers on Linux and launchd agents on Darwin.
[Home Manager Git module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/git.nix)

## Shared defaults

Use these settings in the shared policy. They are portable across Linux and
Darwin and do not encode a personal identity.

```nix
settings = {
  init.defaultBranch = "main";

  fetch = {
    prune = true;
    pruneTags = true;
    recurseSubmodules = "on-demand";
    writeCommitGraph = true;
  };
  feature.manyFiles = true;
  index.threads = 0;
  maintenance.strategy = "incremental";

  diff = {
    algorithm = "histogram";
    colorMoved = "zebra";
    renames = true;
    submodule = "log";
  };
  merge = {
    conflictStyle = "zdiff3";
    stat = true;
  };
  commit = {
    status = true;
    verbose = true;
  };
  status = {
    aheadBehind = true;
    submoduleSummary = true;
  };
  color.ui = "auto";
  branch.sort = "-committerdate";
  tag.sort = "version:refname";
  help.autocorrect = "prompt";
  push = {
    default = "simple";
    autoSetupRemote = true;
    followTags = true;
  };
  rerere.enabled = true;
};
```

`feature.manyFiles` selects index v4 and the untracked cache, which reduce
status and checkout work in large trees. `index.threads = 0` asks Git to size
index loading from the available CPUs. A commit graph written after fetch
speeds history operations such as `merge-base` and graph log. Leave
`fetch.negotiationAlgorithm` at Git's current default unless a benchmark on a
large, high-latency repository demonstrates a gain. It is a transfer-policy
knob, not a general speed switch. [Git configuration reference](https://git-scm.com/docs/git-config),
[index and filesystem monitor reference](https://git-scm.com/docs/git-update-index)

`fetch.prune` keeps remote-tracking branches honest. `fetch.pruneTags` is
useful for a personal checkout, but do not use it for a mirror that deliberately
keeps deleted remote tags. `fetch.recurseSubmodules = "on-demand"` is Git's
default and fetches populated submodules only when a new superproject commit
requires it. Do not set `submodule.recurse = true` globally: it makes many
otherwise local commands visit every submodule.
[Git configuration reference](https://git-scm.com/docs/git-config)

`zdiff3` retains the common ancestor while minimizing conflict regions. It is
substantially easier to resolve than the default two-sided markers. Native
aliases should be short, argument-free Git commands, for example
`st = "status --short --branch"` and `lg = "log --graph --decorate --oneline"`.
Avoid aliases beginning with `!` in the shared module. Git runs those through a
shell from the repository top level, which turns a convenience setting into
code execution. [git-merge](https://git-scm.com/docs/git-merge),
[Git aliases](https://git-scm.com/docs/git-config#Documentation/git-config.txt-alias)

Use `push.default = "simple"` and `push.autoSetupRemote = true`. A normal
first push creates the matching upstream, while the default refuses an
ambiguous branch-name mismatch. `push.followTags` only sends annotated tags
that point at commits being pushed. [Git configuration reference](https://git-scm.com/docs/git-config)

## Safety boundaries

Keep `rerere.enabled = true`, but leave `rerere.autoUpdate` unset or `false`.
Rerere records useful conflict resolutions. With auto-update on, Git also
stages a remembered resolution without review. That is a bad trade for a
global policy. Likewise, do not set `rebase.autoStash` or `merge.autoStash`
globally. Reapplying the temporary stash can itself conflict. Set either in a
personal local include only if the workflow is worth that risk.
[Git configuration reference](https://git-scm.com/docs/git-config)

Do not add `safe.directory = "*"`. Git otherwise refuses to parse a repository
configuration owned by a different user, including its hooks. Add a single
shared checkout path in a local file only when it is genuinely intentional.
For a workstation that does not use bare repositories as remotes, consider
`safe.bareRepository = "explicit"`; Git documents this as protection from a
cloned tree that contains a bare repository. [Git configuration reference](https://git-scm.com/docs/git-config)

Git's built-in protocol policy already treats `http`, `https`, `ssh`, and
`git` as safe, `ext` as forbidden, and `file` as user-initiated only. Preserve
that default. Tightening `protocol.file.allow` globally breaks legitimate local
submodules; loosening it weakens submodule protection. Set
`transfer.credentialsInUrl = "die"` globally, so Git refuses plaintext
passwords or tokens in remote URLs. `transfer.fsckObjects = true` is a
reasonable opt-in for untrusted remotes, but it validates every transfer and
fetch failures can leave unreachable objects. Make it a local trust-boundary
choice rather than paying the cost for every ordinary fetch. [Git configuration
reference](https://git-scm.com/docs/git-config)

## Signing and credentials

Use SSH commit and tag signatures when the user already has a maintained SSH
key:

```nix
programs.git.signing = {
  format = "ssh";
  key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
  signByDefault = true;
};
```

The key path and `gpg.ssh.allowedSignersFile` belong in the local module.
Verification only receives Git's `fully` trust level when the signing public
key appears in the allowed-signers file. Keep that file as a local, reviewed
trust list. Do not pretend that a signature is verified simply because a
commit carries an SSH signature. [Git configuration reference](https://git-scm.com/docs/git-config),
[Git signature format](https://git-scm.com/docs/gitformat-signature)

Use the OS credential store, not `credential-store` and not tokens in remote
URLs. The supported choices here are `osxkeychain` on Darwin and the absolute
Nix-store path to `git-credential-libsecret` on Linux. `credential-cache` is a
reasonable fallback on a headless Linux machine because it keeps credentials
in memory and expires them. It is not persistent storage. Set
`credential.useHttpPath = true` only if separate accounts or tokens must be
kept distinct for repositories on the same HTTP host. [Git credential helpers](https://git-scm.com/doc/credential-helpers),
[gitcredentials](https://git-scm.com/docs/gitcredentials),
[git-credential-cache](https://git-scm.com/docs/git-credential-cache)

## Conditional local configuration

Keep the base config free of `user.name`, `user.email`, `user.signingKey`,
trusted principals, credential usernames, and work remotes. Include small
local files for the personal identity and use `includeIf` for work identity.
`gitdir:` suits a stable checkout root. `hasconfig:remote.*.url:` suits a
repository that may live anywhere, and is the right match for the existing
remote-host identity selection. An included file selected by the latter cannot
declare remote URLs, so keep it to identity and signing settings. [Git
conditional includes](https://git-scm.com/docs/git-config#_conditional_includes)

The local files should be produced from the existing secrets mechanism or be
ignored local files with mode 0600. A public allowed-signers list need not be a
secret, but its principals and membership are still user-specific policy.

## Platform notes and maintenance

Set `core.precomposeUnicode = true` only on Darwin. Git uses it only on macOS
to reverse that platform's Unicode filename decomposition, which avoids
cross-platform filename surprises. Keep `core.fileMode` at its default rather
than setting it false, since hiding executable-bit changes is wrong on Linux.
`core.autocrlf = "input"` is safe for a Unix-only configuration, but attributes
in each repository are the better place to define cross-platform text rules.
[Git configuration reference](https://git-scm.com/docs/git-config)

The built-in `core.fsmonitor = true` gives a real status improvement on large
Darwin trees. Gate it behind `isDarwin` for the shared module. Git's current
configuration documentation only promises the built-in monitor on macOS and
Windows, and older Git versions can mistake the boolean for a hook pathname.
On Linux, retain the untracked cache and enable the monitor only after the
installed Git and filesystem have been tested. Never enable remote filesystem
monitoring by default. [Git filesystem monitor](https://git-scm.com/docs/git-fsmonitor--daemon),
[Git configuration reference](https://git-scm.com/docs/git-config)

Home Manager's `programs.git.maintenance.enable` works on both target systems,
but its scheduler operates only on explicit `maintenance.repositories`.
Keep the absolute repository list in each local home configuration. Prefer
Git's incremental maintenance strategy, which runs small commit-graph and
prefetch jobs hourly, loose-object and incremental-repack jobs daily, and
pack-refs weekly. Do not schedule `git gc` alongside maintenance. Git calls
out the different locking behavior. [Home Manager Git module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/git.nix),
[git-maintenance](https://git-scm.com/docs/git-maintenance)

## Verification

After activation, verify generated policy and platform integration rather than
relying on the rendered file alone:

```sh
git config --show-origin --list
git config --includes --show-origin --get-regexp '^(user|gpg|includeIf)\\.'
git fsck --connectivity-only
git fsmonitor--daemon status
git maintenance run --schedule=daily
```

Test a personal and a work checkout, a repository with a changed remote URL,
an SSH-signed commit and tag, HTTPS credential retrieval after a new login,
and a Linux and Darwin checkout with Unicode filenames. Check the effective
identity with `git var GIT_AUTHOR_IDENT` before creating a commit.
