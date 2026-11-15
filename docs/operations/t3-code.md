# T3 Code desktop and persistent server

The [home module](../../modules/home/dev/agentic-gui/t3-code.nix) uses upstream
Home Manager's `programs.t3code` package, mutable settings merger, and server
service. Local extensions preserve backend identity, provider selection,
private state permissions, and graceful shutdown. Nix owns package versions and
service declarations; T3 owns accounts, connection routes, credentials and
interactive settings.

## Package and configuration ownership

T3 is selected from the official Nixpkgs recipe through the separately locked
`nixpkgs-t3code` input. Update that input deliberately, review the Darwin override
guards, then validate the resulting package. Do not run the curl installer,
`t3 update`, or `t3 service install` over a Nix-managed installation. Those
commands own their own binaries and units and can compete with Home Manager.

As checked on 2026-11-08, upstream's latest stable release is
[0.1.7](https://github.com/pingdotgg/t3code/releases/tag/v0.1.7), while the reviewed
official Nixpkgs recipe still packages 0.1.6. This integration uses the official
recipe's supported package and current upstream configuration methods. It does
not silently bump source/dependency hashes or replace the signed Darwin app
with an unqualified release. Updating to 0.1.7 requires a separate package and
native identity/continuity check, including both temporary Darwin fixes.

The upstream [Home Manager module](https://github.com/nix-community/home-manager/blob/6750249c69969d09d952efaf3fab88a2bdac7ec6/modules/programs/t3code.nix)
already provides mutable merging for `userdata/settings.json`, keybindings and
client settings. This configuration uses that merger to set only the selected
CLI instance drivers, executable paths and Codex home. Unmentioned enabled
flags, models, shadow homes, instance environment and managed-account modes
remain app-owned. Managed account setup mode intentionally remains managed;
changing it is a separate account migration.

## Provider selection

The official package wraps T3 with its own Codex by default. That PATH prefix
can take precedence over a Home Manager-configured CLI. The persistent backend
disables those bundled agent additions and receives the enabled configured
Codex, Claude Code and OpenCode packages explicitly in its environment.
Fallback user-profile and system paths remain available for other providers.
The environment also receives Home Manager's XDG directories, Claude config
directory and optional OpenCode mutable-config selectors. Claude uses Home
Manager's final package so older CLI plugin wrappers remain effective; OpenCode
extra packages remain available on the service PATH. These are explicit
non-secret selectors, not a copy of the login shell's full environment.

T3's configured CLI instances also receive absolute executable paths. Codex
receives both `CODEX_HOME` in the service environment and the matching explicit
instance `homePath`. The latter is needed by T3 0.1.6's continuation identity;
0.1.7 adds support for the ambient environment when no explicit home is set.
The existing Codex launcher still respects explicit environment overrides in
standalone use. See [harness integration](../agents/harnesses.md).

Authentication belongs to the user running the service. Installing a CLI or
writing an executable path does not authenticate it. Verify each enabled
provider in T3's settings after activation, without copying credentials into
Nix expressions, unit files or the Nix store.

## One server per state directory

The server runs `t3 serve` with loopback host, port 3773 and the existing `.t3`
base directory. Its unit name and Darwin label remain stable. The backend
package is separate from GUI-only metadata/signature changes, so those changes
do not by themselves replace an unchanged backend command.

Home Manager's native settings and server options remain available. For example,
`programs.t3code.server.enable = false` selects client-only operation. Replacing
`server.extraArgs` is an explicit configuration decision: retain the intended
base directory and listener behavior.

When using the persistent server, disable the desktop's embedded local backend
through the desktop settings API before starting a second owner. The control
is stored in the separate `desktop-settings.json`, not the Home Manager-managed
`client-settings.json`. Do not manufacture that flag in `clientSettings` or
rewrite the encrypted saved-environments catalog. Connect the app to the saved
authenticated server route instead. A state lock conflict exits with code 78;
the Linux unit suppresses automatic restart for that exit.

Linux's user manager needs lingering for operation after logout. The desktop
host already declares it. On macOS a user LaunchAgent is tied to its configured
login domain; do not promise headless-before-login availability from a user
LaunchAgent alone.

## Updates and activation

Check the task queue and active T3 work before activation. Restarting the server
interrupts agent turns, terminals and connected clients. Linux uses
`X-SwitchMethod=keep-old`, so installing a new unit does not automatically
replace the running backend. After work drains, explicitly restart the managed
unit to adopt its new package/environment. Until then, a new generation is not
proof that the running server changed.

Home Manager's Darwin activation replaces a changed plist. Its restart triggers
are not an active-work drain mechanism or a keep-old policy. Apply a Darwin
backend/unit update only after arranging an interruption window and preserving
state. Both services retain a 90-second stop deadline. Preserve user-owned
accounts and connection catalogs throughout; an unexpected initialization is a
failure, not an invitation to create a replacement account.

Use the native manager to inspect the Nix-managed service:

```sh
# Linux
systemctl --user status t3code.service
journalctl --user -u t3code.service

# macOS, in the service user's login session
launchctl print "gui/$(id -u)/com.t3tools.t3code.service"
```

`programs.t3code.server.environmentFile` remains supported for runtime
environment values. The launchd wrapper reads it at execution time. Keep secrets
outside source and the Nix store. Paths and arguments are rendered with the
repository's Bash template helper.

## Access and acceptance

Loopback binding avoids a new unauthenticated LAN listener. Preserve the existing
private forwarding and saved authenticated routes. For a new remote device,
follow upstream's [remote access](https://github.com/pingdotgg/t3code/blob/2359643cffa6ba9ee84d6f2694b935de54a8013e/docs/user/remote-access.md)
flow; do not replace pairing with a public port or copy tokens into configuration.
Upstream [background-service guidance](https://github.com/pingdotgg/t3code/blob/2359643cffa6ba9ee84d6f2694b935de54a8013e/docs/user/background-service.md)
explains lifecycle and platform limits; Home Manager owns the equivalent service
installation here.

`checks.<system>.t3code` exercises the real Home Manager module with a finite
backend fixture. It verifies provider-wrapper selection, CLI homes and config
selectors, extra tool availability, argv, disabled-server behavior, and stable
backend identity across GUI-only changes. It also executes the native settings
merger against private fixture state to check preservation of enabled flags,
models, shadow homes, other instances and private file mode. It does not start
another real T3 server or touch account state.

Native rollout additionally needs provider login/discovery under the service
environment, continuation of an existing thread, expected logout/boot behavior,
authenticated reconnection, and a deliberate graceful restart. Darwin also needs
the existing signed-app, Keychain/catalog and Local Network acceptance checks.
Schema, evaluation and fixture passes do not establish those runtime results.
