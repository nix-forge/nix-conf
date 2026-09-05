# Codex Desktop remote SSH and Nushell

Research date: 2026-09-02

## Conclusion

The SSH connection is reaching the desktop. It fails before Codex starts because
OpenSSH gives the remote command to the account's password-database shell, and
that shell is Nushell 0.115.1. The command shipped in ChatGPT Desktop build
`26.818.41705` is quoted for a POSIX shell. Nushell rejects that text while
parsing it.

Set the desktop account's login shell to `pkgs.bashInteractive`. In this repo the
right declaration is the user record in `hosts/nixos/desktop/default.nix`:

```nix
homes.ianmh.user.shell =
  inputs.nixpkgs.legacyPackages.x86_64-linux.bashInteractive;
```

The framework copies that record into `users.users.ianmh`. A user-specific
change is preferable to changing `users.defaultUserShell`, since no other
account needs to move.

The desktop Home Manager profile must make the same choice. Its aggregate
`shells` selector imports every file below `modules/home/shells`, including the
Nushell module. Replace that aggregate selector with the explicit Bash support
modules listed below. This keeps the shell policy visible and prevents a future
Nushell setting from becoming active through the directory aggregate.

`bashInteractive` is intentional. The pinned NixOS option accepts a shell
package and uses `pkgs.bashInteractive` as its example. The Bash module also
uses it as NixOS's default user shell. In this nixpkgs revision, `pkgs.bash` and
`pkgs.bashInteractive` are the same derivation, while `bashNonInteractive` is a
separate build. The explicit name records that this is a human login shell.
[Pinned user option](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/config/users-groups.nix#L259-L271),
[pinned Bash module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/programs/bash/bash.nix#L224),
[pinned package aliases](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/top-level/all-packages.nix#L3065-L3072)

## Why the `nu)` branch does not help

OpenAI documents that the desktop app starts the remote Codex app server over
SSH using the remote user's login shell. OpenSSH is more specific: when a client
supplies a command, `sshd` runs it through that shell with `-c`. It takes the
shell from the system password database. [OpenAI remote-connections
documentation](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host),
[OpenBSD `sshd(8)`](https://man.openbsd.org/sshd#DESCRIPTION),
[OpenSSH execution source](https://github.com/openssh/openssh-portable/blob/master/session.c#L1636-L1671)

The signed local app's `Contents/Resources/app.asar` archive contains this logic
in the `.vite/build/main-dcf3zoVL.js` member:

```javascript
function JS(value) {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

// Reduced from YS(...)
return `sh -c ${JS([
  // ...
  `csh|tcsh) ...`,
  `nu) exec "$SHELL" -l -i -c ...`,
  // ...
].join(" "))} sh ${JS(payload)}`;
```

`JS` uses the POSIX `'\''` idiom to place an apostrophe inside a
single-quoted word. OpenSSH first invokes `nu -c` on the entire generated
command. Nushell therefore has to parse those POSIX escapes before `sh -c` can
run and reach the `nu)` case. It fails at the first escaped quote before the csh
payload, which is why the diagnostic points near `csh|tcsh` rather than at the
actual cause.

Nushell's own documentation warns that it is not POSIX-compatible and that
using it as a login shell can break programs which assume a POSIX shell. This
is one of those cases. Changing Nushell versions would leave the same contract
mismatch in place. [Nushell default-shell warning](https://www.nushell.sh/book/default_shell.html#setting-nu-as-login-shell-linux-bsd-macos),
[Nushell command-string behavior](https://www.nushell.sh/book/configuration.html#flag-behavior)

## Bash-only desktop policy

The desktop should use Bash for login sessions, interactive terminals, and
programs that inspect `SHELL`. Do not preserve a terminal-specific or SSH-only
Nushell path.

The framework generates the `shells` selector as a directory aggregate. For
the desktop profile, replace it with the modules that configure Bash and the
shell-independent command-line tools:

```nix
shells-aliases
shells-atuin
shells-bash
shells-carapace
shells-eza
shells-fzf
shells-integration
shells-starship
shells-tmux
shells-zoxide
```

Do not include `shells`, `shells-nushell`, any `shells-nushell-*` selector, or
`shells-zsh` in this Bash-only profile. The explicit list also removes the
duplicate shell selectors which appeared both before and after the aggregate
in `homes/desktop/default.nix`.

The Bash module should set:

```nix
home.sessionVariables.SHELL = lib.getExe pkgs.bashInteractive;
```

Leave Ghostty's `command` unset. Ghostty checks `SHELL` first and the password
database second, so both routes now select Bash. [Ghostty `command`
reference](https://ghostty.org/docs/config/reference#command)

This policy should evaluate with `programs.bash.enable = true` and
`programs.nushell.enable = false`. Nushell's parser remains relevant to the
root-cause record above, but it is no longer part of the desktop configuration.

## Reproduction and evaluation

I reconstructed the `JS` and `YS` functions from the installed app and used a
harmless `printf` payload. Nushell 0.115.1 reproduced the report exactly:

```text
nu: status=1
Error: nu::parser::parse_mismatch
Parse mismatch: expected operator.
[source:1:286]
```

The identical generated command under Bash printed
`CODEX_BOOTSTRAP_OK` and exited zero. This isolates the failure to parsing by
the password-database shell. It does not depend on SSH keys, Codex
authentication, or whether `codex` is already installed.

After the user-shell declaration, evaluation succeeded without building:

```text
$ nix eval --raw .#nixosConfigurations.desktop.config.users.users.ianmh.shell.name
bash-interactive-5.3p15

$ nix eval --raw .#nixosConfigurations.desktop.config.users.users.ianmh.shell.shellPath
/bin/bash
```

After replacing the aggregate Home Manager selector, verify the complete
Bash-only policy with evaluation only:

```sh
nix eval --json \
  .#nixosConfigurations.desktop.config.home-manager.users.ianmh.programs.bash.enable
nix eval --json \
  .#nixosConfigurations.desktop.config.home-manager.users.ianmh.programs.nushell.enable
nix eval --raw \
  .#nixosConfigurations.desktop.config.home-manager.users.ianmh.home.sessionVariables.SHELL
```

The expected results are `true`, `false`, and a Bash path ending in
`/bin/bash`, respectively.

Do not build this NixOS closure locally on the Mac. The repository's desktop
node in `flake/deploy.nix` sets `remoteBuild = true`, uses `desktop` as the host,
and activates as `root`. Apply it through that deploy-rs node so the x86_64
desktop performs the build:

```sh
deploy .#desktop
```

No build or deployment was run during this research.

After deployment, verify the boundary before reconnecting it in the app:

```sh
ssh desktop 'getent passwd ianmh | cut -d: -f7'
ssh desktop 'printf "%s\n" REMOTE_COMMAND_OK'
ssh desktop 'command -v codex && codex --version'
```

The first command should end in `/bin/bash`; the other two should complete
without a Nushell parser error. Then enable the host again under **Settings >
Connections > SSH**.
