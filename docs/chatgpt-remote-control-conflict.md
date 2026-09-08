# ChatGPT remote control conflict on desktop

Investigated 2026-09-07 UTC, using ChatGPT Linux 26.901.41600 and Codex CLI
0.149.0.

## Cause

The Nix package was not responsible for the reported failure. An SSH-started
Codex app server already owned the remote connection for this computer. The
desktop app's bundled server tried to connect with the same installation and
server enrollment, and OpenAI returned HTTP 409 with
`Remote app server already online`.

There was one main ChatGPT GUI process, but two independent app servers:

| Process at diagnosis | Launch | Remote status before the fix |
| --- | --- | --- |
| PID 4161 | Standalone `codex -c features.code_mode_host=true app-server --listen unix://`, started through SSH | Connected |
| PID 1215028 | App server bundled with the running ChatGPT GUI | Errored, retrying HTTP 409 |

Both used `~/.config/codex`. The SSH server had no loaded tasks. Its socket was
`~/.config/codex/app-server-control/app-server-control.sock`.

The app's renderer maps any remote status of `errored` to the toast suggesting
another instance is running. In this case, the transport logs confirmed that
suggestion. Do not diagnose every occurrence of that toast as a duplicate
process without checking the underlying error.

## Fix applied

Sent `remoteControl/disable` to the SSH server over its existing local socket.
The response and a subsequent `remoteControl/status/read` both reported
`disabled`. SSH transport remained available, and the GUI process continued
running.

The command saved the standalone enrollment's remote-control preference as
false. The separate `Codex Desktop` enrollment kept its preference set to true.
These preferences live in `state_5.sqlite`, in `remote_control_enrollments`.
The database was inspected read-only; the app-server API performed the change.

`codex app-server daemon disable-remote-control` was tried first, but rejected
the server because the app's older SSH bootstrap had started it with `nohup`
rather than registering it as a managed daemon. That command made no change.

No package, wrapper, firewall, sandbox, or shared TOML setting needed changing.
Avoid enabling remote control on the standalone SSH server while using the
GUI's "Control this PC" connection for the same installation.

## Verification

The transport logs in `~/.config/codex/logs_2.sqlite` recorded:

```text
06:52:43 UTC, GUI server: HTTP 409, Remote app server already online
06:52:46 UTC, SSH server: connection_end_reason=Disabled
06:53:14 UTC, GUI server: previous_status=Errored next_status=Connected
06:53:14 UTC, GUI server: connected to app-server remote control websocket
```

A fresh standalone server was also launched on a temporary Unix socket using
the original SSH process's executable and environment. After initialization as
a desktop client, `remoteControl/status/read` returned `disabled`. The temporary
server was stopped. This verifies that the saved preference survives a fresh
SSH-style launch without adding a wrapper or editing application code.

This verifies the server connection and the persistence fix. Pairing a phone
and controlling a task from it remain separate end-to-end checks.

## Diagnostic protocol notes

The app-server control socket carries WebSocket traffic, not newline-delimited
JSON directly. `app-server proxy` forwards that WebSocket stream unchanged.
For a local diagnostic client, connect to the Unix socket using
`ws://localhost/`, disable WebSocket compression, and send:

1. `initialize`, with `clientInfo` and `capabilities.experimentalApi = true`.
2. The `initialized` notification.
3. `remoteControl/status/read` and `thread/loaded/list` for read-only checks.
4. `remoteControl/disable` only when deliberately releasing this server's
   remote connection.

Match responses by request ID because notifications can arrive between them.
Do not print authentication data, enrollment identifiers, or full log dumps.

## Official documentation

[OpenAI's Linux app guide](https://learn.chatgpt.com/docs/linux/linux-app)
describes the Linux preview and formally supported distributions. NixOS is
outside that list. The same guide distinguishes Linux desktop support from
Computer Use, which is not yet supported in the Linux preview.

[Remote](https://learn.chatgpt.com/docs/remote) and
[remote connections](https://learn.chatgpt.com/docs/remote-connections) describe
remote access and SSH setup. The public Remote overview names Mac and Windows
hosts. The successful Linux connection recorded here is a local observation,
not a claim that OpenAI formally supports every Remote workflow on NixOS.
