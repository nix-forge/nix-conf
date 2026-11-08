# PATH precedence in ChatGPT and development applications

Reviewed: 2026-10-13. Research only. ChatGPT source was checked at Nixpkgs
`dd50db5f2a6b182888b2ee30bd23c0efeaa7b942`; PR #573415 at
`d42f9ff736dd8ea55fe3316d3d6c56fecead9fc4`. Other package recipes were inspected
at the review baseline `1adc3e234ad1dcd8f166c072a0d51ae24bb72255`.

## Answer

Prince213 asks whether more dependencies of ChatGPT should become PATH
fallbacks. The comment does not require a repository-wide conversion. The best
small follow-up candidates are ChatGPT's `xdg-utils` and `lsb-release`.
OpenCode's ripgrep wrapper is a strong independent candidate because upstream
explicitly searches the caller's PATH first. VS Code/Cursor need a more involved
separation of launcher dependencies from the environment inherited by project
processes. [Prince213's review](https://github.com/NixOS/nixpkgs/pull/573415#pullrequestreview-5500419192).

Keep the current Git PR small. Moraxyc explicitly requested only the Git wrapper
change, and the current patch follows that request. A separate change can
address desktop helpers without mixing in launcher restructuring or sandbox
selection. [Inline request](https://github.com/NixOS/nixpkgs/pull/573415#discussion_r4255952092).

## What prefix and suffix mean

Executables are resolved from left to right on PATH. A wrapper's
`--prefix PATH : ...` puts its dependencies ahead of inherited commands.
`--suffix PATH : ...` preserves inherited command selection and supplies
fallbacks. A project shell's Git wins with a suffix; packaged Git wins with a
prefix. Appending retains the dependency in the Nix closure.

The Nixpkgs manual recommends prefixes for explicit dependencies and suffixes
when resolution should happen at runtime. It also recommends patching paths
directly where appropriate. The shell wrapper avoids adding a suffix directory
already on PATH; a prefix can move an existing entry to the front.
[Manual](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/doc/stdenv/stdenv.chapter.md#fun-makeWrapper),
[implementation](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/build-support/setup-hooks/make-wrapper.sh#L50-L105).

Developers reasonably choose Git, runtimes, formatters, and compilers per
project. Operational helpers may require GNU utility options or sandbox
capabilities. Absolute helper paths can protect those requirements without
replacing tools in every child process. This is a design recommendation, not a
universal rule that runtime dependencies must be prefixed.

## ChatGPT dependencies

The [current recipe](https://github.com/NixOS/nixpkgs/blob/dd50db5f2a6b182888b2ee30bd23c0efeaa7b942/pkgs/by-name/ch/chatgpt/package.nix)
supplies absolute Node, ripgrep, and Tectonic resource paths. It defaults
`CODEX_BROWSER_USE_NODE_PATH` and `NODE_REPL_NODE_PATH` to managed Node paths.
Those contracts matter when considering the remaining PATH entries.

| Dependency | Recommendation | Reason and remaining evidence |
| --- | --- | --- |
| Git Minimal | Keep the existing suffix change. | Preserve caller Git and retain fallback availability. This is the present PR's entire change. |
| xdg-utils | Best additional small change: suffix. | Honor a caller's opener wrapper or desktop policy. Validate URI/file opening and portal behavior. |
| lsb-release | Reasonable companion change: suffix; lower practical benefit. | Distribution reporting has no identified application-specific version requirement. |
| Coreutils | Avoid an outer-wrapper-only change. | The inner launcher prefixes Coreutils again. Actually restoring caller priority requires a separate launcher change. |
| Bubblewrap | Plausible separate change after sandbox validation. | Current source-built Codex supports eligible host bubblewrap and probes capabilities. Check the bundled backend separately. |
| Node and npm/npx | High potential project benefit; defer until runtime checks. | Known internal paths are managed explicitly, but plugin/MCP subprocesses can still use bare commands. |

For desktop helpers, remove `xdg-utils` and `lsb-release` from the prefix list
and append them alongside Git. Leave other dependencies unchanged in that
patch. Use disposable conflicting-PATH and minimal-PATH probes plus a real
desktop opener check. Another permanent test framework is unnecessary for this
wrapper-list edit.

The [xdg-utils package](https://github.com/NixOS/nixpkgs/blob/dd50db5f2a6b182888b2ee30bd23c0efeaa7b942/pkgs/by-name/xd/xdg-utils/package.nix)
contains NixOS portal integration. Choosing the caller executable can change
that policy. [OpenAI #52073](https://github.com/openai/codex/issues/52073) reports
a MIME/browser-default problem; it demonstrates relevance of desktop
integration, but does not establish that suffixing fixes that issue.
[The lsb-release implementation](https://github.com/NixOS/nixpkgs/blob/dd50db5f2a6b182888b2ee30bd23c0efeaa7b942/pkgs/by-name/ls/lsb-release/lsb_release.sh)
reads host `os-release` information and binds its own helper dependencies.

### Coreutils layering

[The launcher](https://github.com/NixOS/nixpkgs/blob/dd50db5f2a6b182888b2ee30bd23c0efeaa7b942/pkgs/by-name/ch/chatgpt/launcher.nix)
uses `writeShellApplication` with Coreutils and flock in `runtimeInputs`.
[That builder](https://github.com/NixOS/nixpkgs/blob/dd50db5f2a6b182888b2ee30bd23c0efeaa7b942/pkgs/build-support/trivial-builders/default.nix#L318-L324)
prepends runtime inputs. The final exec inherits that environment. Suffixing
Coreutils only in the outer wrapper therefore fails to restore caller priority.

A useful follow-up would bind required launcher utilities to absolute paths,
or prevent the launcher's operational PATH changes from escaping into ChatGPT.
Audit both the launcher and helper scripts. Preserve cache locking and recovery;
validate the complete generated launcher rather than its argument list alone.

### Sandbox and Node qualifications

Current Codex checks eligible host bubblewrap paths, probes capabilities, and
uses a packaged fallback when necessary. Therefore "bubblewrap must always be
prefixed" is too strong. A host-first change can follow upstream's intended
design, but needs a real sandbox-command check for default and `codex = null`
modes. [PATH search](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/sandboxing/src/bwrap.rs#L179-L206),
[selection and probing](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/linux-sandbox/src/launcher.rs#L135-L219).

[OpenAI #21246](https://github.com/openai/codex/issues/21246) and
[#19562](https://github.com/openai/codex/issues/19562) report incompatible Node
versions on Windows. Their errors recommend `NODE_REPL_NODE_PATH`, which the
Nix package supplies. They establish a compatible-runtime requirement, not
proof that Linux suffixing breaks the current managed defaults.

Before moving Node/npm, check browser startup, Node REPL, an npm/npx MCP server,
and a project task with a different caller Node. Repeat without caller Node and
with both backend modes. Inspect final task environments because shell
hydration can alter PATH after wrapping. A static search cannot establish every
closed-source plugin's behavior. Keep Node and npm policies consistent; a
managed npm entry-point shebang does not pin every lifecycle child process.

## Applications selected in this repository

Both home profiles select `dev`, VS Code, Neovim, Ghostty, Feishin, and Prism
Launcher. The module framework aggregates descendants for directory selectors
without a default module, so `dev` includes the agent applications. The
activated Linux user profile also contains ChatGPT, Codex CLI, Claude Code,
OpenCode, VS Code, Cursor, Neovim, Ghostty, and Feishin. Declarations do not prove
activation, and an activated package need not match current upstream source.
[Desktop home](../../homes/desktop/default.nix),
[macOS home](../../homes/macbook-pro-m4/default.nix),
[selector implementation](../../nix-config-framework/lib/default.nix).

### OpenCode: strong independent candidate

The activated OpenCode 1.18.33 wrapper prefixes ripgrep. The inspected Nixpkgs
1.19.0 recipe does the same, adding `sysctl` on Darwin.
[Recipe](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/by-name/op/opencode/package.nix#L162-L174).

Upstream explicitly checks caller PATH for `rg` before using or downloading a
fallback in both [1.18.33](https://github.com/anomalyco/opencode/blob/v1.18.33/packages/core/src/ripgrep/binary.ts#L90-L105)
and [1.19.0](https://github.com/anomalyco/opencode/blob/v1.19.0/packages/core/src/ripgrep/binary.ts#L90-L105).
The Nix prefix overrides that preference.

Propose a small PR appending ripgrep while preserving Darwin's sysctl prefix.
Verify file enumeration and JSON search with a caller wrapper and without
caller ripgrep. Arbitrarily old/incompatible ripgrep builds are not guaranteed
to support the flags and output expected by the application. The activated
profile and wrapper currently provide the same ripgrep version; ordinary
profile use has not demonstrated a local mismatch.

### VS Code and Cursor: useful audit, larger change

Both activated wrappers prefix GLib, awk, grep, sed, Coreutils, which, and
getconf. Cursor uses the shared VS Code builder. Editor children initially
inherit those choices, although shells and extensions can later alter PATH.
Git and Node are absent from this list, so another caller-Git fix here has no
basis. [Shared builder](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/applications/editors/vscode/generic.nix#L378-L400),
[Cursor recipe](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/by-name/co/code-cursor/package.nix).

These dependencies support real helpers. VS Code's
[process-inspection script](https://github.com/microsoft/vscode/blob/1.139.1/src/vs/base/node/ps.sh)
uses getconf, awk, sed, and Coreutils commands. A blanket suffix also changes
those helpers. Audit command use, bind operational tools explicitly where
practical, and then preserve project PATH for tasks. Validate process
inspection, trash operations, CLI launch, terminals, and extension tasks.
This is a follow-up project, not a verified one-line change.

### Feishin: small candidate, little benefit here

Upstream prefixes `mpv-unwrapped` on Linux and Darwin.
[Recipe](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/by-name/fe/feishin/package.nix#L90-L108).
It originally added mpv for playback and later selected the unwrapped output
to avoid unnecessary dependencies. [PR #459155](https://github.com/NixOS/nixpkgs/pull/459155),
[PR #495910](https://github.com/NixOS/nixpkgs/pull/495910).

A suffix can honor caller mpv when the player uses bare-command fallback.
Upstream prioritizes configured binary paths and also checks common Homebrew
paths on macOS. [Player resolution](https://github.com/jeffvli/feishin/blob/v1.17.0/src/main/features/core/player/index.ts#L128-L173).
This repository already configures an explicit private mpv launcher through
[the Feishin module](../../modules/home/feishin.nix), so PATH changes do not
improve its configured selection. Treat this as lower priority, with playback
and IPC validation, and preserve the working local integration.

### Cases without a demonstrated need

- Claude Code prefixes procps, ripgrep, bubblewrap, and socat for process cleanup,
  search, and sandboxing. No concrete project mismatch was established.
  [Recipe](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/by-name/cl/claude-code/package.nix#L57-L81).
- Activated Codex CLI 0.159.3 prefixes ripgrep/bubblewrap, but inspected Nixpkgs
  0.162.1 supplies package-relative managed resources instead. Review that design
  before proposing a patch to an older installed wrapper.
  [Recipe](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/by-name/co/codex/package.nix#L240-L246).
- Nixpkgs Neovim already appends runtime dependencies. The activated Neovim Lua
  configuration also appends provider tools.
  [Wrapper](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/applications/editors/neovim/wrapper.nix#L274-L279).
- The activated Ghostty wrapper alters GLib/GStreamer search variables, without
  a PATH prefix. Library and plugin search paths are outside this proposal.
- Prism Launcher adds lspci/xrandr plus optional `additionalPrograms`. No
  nonempty customization was identified here. Its separate Java-path setting
  is not PATH. No demonstrated issue justifies changing its defaults here.
  [Recipe](https://github.com/NixOS/nixpkgs/blob/1adc3e234ad1dcd8f166c072a0d51ae24bb72255/pkgs/by-name/pr/prismlauncher/package.nix#L120-L135).

## Related editor work and local policy

[Nixpkgs #548951](https://github.com/NixOS/nixpkgs/issues/548951) tracks extension
defaults that override project tool discovery. Bash IDE, ShellCheck, Tinymist,
and Oxc overlap with extensions selected here. The issue distinguishes harmful
defaults from necessary fixes for bundled executables that cannot run on
NixOS. Check current recipes and existing fixes before proposing another PR.
The [mypy fix](https://github.com/NixOS/nixpkgs/pull/380338) merged; the
[R fallback proposal](https://github.com/NixOS/nixpkgs/pull/549025) remained open
when inspected. Neither establishes a new issue with this configuration.

These homes obtain extensions through `nix4vscode`, so a Nixpkgs extension
recipe defect does not automatically affect the selected VSIX. Local settings
also deliberately bind ShellCheck, shfmt, Ruff, Oxc, Tinymist, and nixd to
absolute paths. Wrapper suffix changes do not override those settings. Preserve
them unless project-specific tool selection is the desired local policy. Then
audit each extension's discovery order and workspace overrides.
[Shell tools](../../modules/home/vscode/languages/bash.nix),
[Python](../../modules/home/vscode/languages/python.nix),
[JavaScript](../../modules/home/vscode/languages/javascript.nix),
[Typst](../../modules/home/vscode/languages/typst.nix),
[Nix](../../modules/home/vscode/languages/nix.nix).

## Recommended order and limits

1. Finish the Git-only PR, keeping its test scaffolding removed.
2. Prepare a small ChatGPT desktop-helper follow-up for xdg-utils/lsb-release
   and validate caller selection, missing-command fallback, and desktop opening.
3. Prepare an OpenCode ripgrep fallback change, preserving Darwin sysctl;
   validate actual search operations.
4. Investigate ChatGPT Node/npm and launcher PATH inheritance with runtime
   probes. Keep sandbox selection separate.
5. Audit shared VS Code/Cursor helpers and selected extension policies.
   Feishin has lower local priority because an explicit path already controls it.

This investigation read package source, primary GitHub conversations, module
declarations, activated Linux shell wrappers, compiled-wrapper argument
strings, and the installed Neovim Lua PATH assignment. A limited scan of the
older installed ChatGPT archive confirmed managed browser Node selection, but
did not cover every current plugin runtime. No package builds, application
sessions, sandbox/MCP tests, macOS activation inspection, configuration changes,
or GitHub writes ran for this research. Search results do not prove that no
related issue exists. The proposals need their stated runtime checks before
being described as ready to merge.
