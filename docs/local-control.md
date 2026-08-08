# Local control services and Windows development VM

This Home Manager configuration runs a private local application stack on macOS
and provides host-only SSH access to a Windows development VM.

## Local application stack

`homes/macbook-pro-m4/local/local-control.nix` manages PostgreSQL, an API, a
background worker, a dashboard development server, and an mTLS reverse proxy
through launchd. The public configuration uses only generic service names.
Project-specific paths, commands, database variable names, and credentials stay
in a local owner-only environment file. Activate it with:

```bash
just home-switch ianmh@macbook-pro-m4
```

Runtime state is stored under `~/.local/state/local-control` with owner-only
permissions. PostgreSQL, the browser API, and the dashboard bind to loopback.
The reverse proxy binds only to the VMware host-only interface and requires a
client certificate before forwarding requests.

The private environment file is
`~/.local/state/local-control/environment`; it is intentionally outside this
repository. Activation does not create a placeholder file: if it is missing or
empty, the launchd service guards exit successfully and remain stopped, so
launchd does not repeatedly restart them. The file must be a regular,
owner-readable file with no group or other permissions.

It is a shell environment file and must provide these generic settings before
the services can run:

- `LOCAL_CONTROL_PROJECT_DIRECTORY`
- `LOCAL_CONTROL_DATABASE_URL`
- `LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE`
- `LOCAL_CONTROL_SCHEMA_COMMAND`
- `LOCAL_CONTROL_API_COMMAND`
- `LOCAL_CONTROL_WORKER_COMMAND`
- `LOCAL_CONTROL_FRONTEND_COMMAND`
- `LOCAL_CONTROL_PREPARE_COMMAND`
- `LOCAL_CONTROL_PREPARATION_INPUT`
- `LOCAL_CONTROL_READINESS_URL`
- `SERVICE_PROXY_ATTESTATION`

The database environment-variable name and every project-specific command are
therefore private. Treat command settings as trusted owner-controlled shell
commands. `LOCAL_CONTROL_PREPARATION_INPUT` is an owner-selected release or
input identifier. Run `local-control-prepare` after changing the checkout,
commands, or preparation input. It runs the locked dependency/setup command and
writes an owner-only proof bound to the canonical checkout path, repository
revision, tracked and untracked source inputs, preparation input, and setup
command. The API, worker, and dashboard launch guards require that proof;
launchd never installs dependencies at runtime.

After preparation succeeds, use `local-control-restart` to ask launchd to start
the guarded application services. The command skips the optional proxy when it
is disabled.

The PostgreSQL data directory is initialized only when it is empty and owned by
the current user with mode `0700`. Existing directories are never chmodded into
compliance: symlinks, non-owner directories, group/world access, missing
control files, incompatible versions, and failed PostgreSQL control-data
validation make activation stop without deleting or reinitializing data.
Private keys remain under
`~/.local/state/local-control/pki` and are not committed to this repository.
Check the services with:

```bash
local-control-status
```

## Windows development VM

`homes/macbook-pro-m4/local/dev-vm.nix` discovers a VMware host-only DHCP lease
and exposes the VM through the `dev-vm` SSH alias. The VM may use NAT for
outbound access, but administrative access stays on the host-only interface.

Verify the host-only connection and common development tools with:

```bash
dev-vm-status
```

The SSH configuration deliberately creates no local port forwards. Keep Mac and
Windows checkouts independent and exchange work through Git or Codex handoff
rather than a shared writable source directory.

Generated client identity files can be copied from the local PKI directory to a
private directory on the VM when an application requires mTLS. Keep the private
key readable only by the Windows user that runs the client.
