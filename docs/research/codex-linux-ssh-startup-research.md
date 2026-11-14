# Codex Linux SSH startup

Reviewed: 2026-10-04. Scope: Linux desktop app 26.924.20706 on x86_64,
connecting to a macOS arm64 host running Codex CLI 0.156.1.

## Answer

Two independent client failures caused endless loading before remote server
startup. First, the app's early shell-environment loader spawned a child before the
native runtime finished installing its SIGCHLD handler. Native startup replaced
libuv's handler, so exited SSH, Git, and shell children remained zombies and
their completion promises never resolved.

Defer Linux shell hydration until `app.whenReady()` resolves, then cross one
event-loop turn with `setImmediate`. Waiting for `whenReady()` alone is
insufficient: its promise callbacks can run before native startup unwinds.
The patched full app loaded the saved alias and completed remote app-server
initialization when reusing an existing SSH master. A subsequent fresh-connection
test exposed a second failure: verbose SSH with `ControlMaster=auto` and
`ControlPersist` leaves stderr open in the background master. The remote command
exits, but Node's `close` event waits for that inherited pipe to close.

The SSH transport now passes `ControlMaster=no` and `ControlPath=none` so its
commands use dedicated connections. Terminal SSH configuration is unchanged.
This is a local workaround, not an upstream fix claim.

## Findings and sources

The [official remote-connections guide](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host)
describes SSH access to remote project files and commands. The remote login
shell must find an authenticated `codex` installation. Terminal SSH, remote Bash,
and remote Codex were working during this investigation.

The installed app's `app.asar` starts with `early-bootstrap.js`, which loads
startup requirements before the main bootstrap. Those requirements invoke the
shell-environment loader. Delaying only the later main-window hydration call
does not fix the first spawn and failed in a separate test instance.

Private process traces showed libuv installing a SIGCHLD handler through
`uv_spawn`, followed by native startup replacing it without preserving the old
handler. Children exited successfully at the operating-system level, but the
app never reaped them. The original process had over a thousand zombie children.
Raw traces and app state are retained outside the repository.

A minimal app in the same runtime reproduced the distinction: a child surviving
across early startup emitted output but no `exit` or `close` event. Starting the
first child after readiness and `setImmediate` produced both events. Neither
changing the executable to an absolute path nor bypassing the package launcher
resolved the full-app failure.

A fresh, private multiplex socket reproduced the second failure using the app's
exact remote probe: the command returned its marker but completion timed out.
The same probe with multiplexing disabled completed in about 250 ms. Omitting
verbose mode also completed, identifying retained debug output as the relevant
difference. OpenSSH's [client implementation](https://github.com/openssh/openssh-portable/blob/master/ssh.c)
retains stderr while detaching a persistent master in debug mode. Dedicated
connections avoid this interaction while preserving the app's SSH diagnostics.

The [Linux preview guide](https://learn.chatgpt.com/docs/linux/linux-app) does
not offer local Computer Use and does not list NixOS among formally supported
distributions. Those support limits do not explain away this reproduced bug.
SSH project access does not itself establish remote graphical control. The
[Computer Use guide](https://learn.chatgpt.com/docs/computer-use) describes
separate macOS permissions and plugin setup; Linux-to-Mac graphical control
over SSH was not tested here.

## Validation and limits

The [runtime regression probe](../../tests/codex/check_ssh_startup.py) loads the
package's actual shell-environment module inside a disposable Owl application,
then checks command output and child completion. It uses a temporary home and
requires no account, network connection, or configured SSH alias:

```sh
python3 tests/codex/check_ssh_startup.py /nix/store/<PACKAGE>/lib/chatgpt
```

The original package failed with `Shell hydration: timed_out`. The patched
runtime passed with `PASS: shell hydration and child completion`.

Supply a configured alias to additionally check the package's actual SSH
argument builder against a fresh multiplex socket:

```sh
python3 tests/codex/check_ssh_startup.py /nix/store/<PACKAGE>/lib/chatgpt <SSH_ALIAS>
```

This integration check requires working noninteractive SSH. It forces a short
persistence timeout for an unpatched master and detects whether the command
leaves a master behind at exit. The hydration-only fix failed this check; the
combined fix passed both checks. Unlike the initial full-app test, it cannot
accidentally pass by reusing a terminal's existing master.

The rebuilt Nix package passed the same probe and completed a full SSH connection
in an isolated app profile with no shell hydration timeout. Evaluation of the
desktop Home Manager package list selected that exact output. The temporary-fix
check passed, including rejection of changed source hashes and versions.
Python lint and formatting, relative documentation links, whitespace, and the
publication scan passed. No full system build or activation was needed.

A full-app profile copied from existing settings reached `connected` with the
combined fix and remote initialization complete. Fresh remote probe and bootstrap
commands each completed in under half a second. Earlier hydration-only tests
occasionally needed a proxy retry, and missed the multiplex failure by reusing a
master. The existing app process was kept running, so the primary session still
needs a restart onto the corrected package.

## Repository integration

The temporary fix at `overlays/temporary/codex-linux-child-exit.nix` limits
application to the reviewed version and rejects changed shell-loader or SSH
argument-builder entry points or source hashes. The Home Manager module consumes the overlaid package so the correction
reaches the installed application. The macOS application remains outside this
Linux override.

Remove the workaround when the unmodified app passes the runtime probe and a
fresh SSH connection without accumulating zombies or retaining multiplex pipes. Recheck native
startup ordering on each app update; the version boundary is a review guard,
not a claim about which future release fixes the bug.
