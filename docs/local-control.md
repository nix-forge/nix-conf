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
repository. Activation creates an empty regular file with mode `0600` when it
does not exist and refuses symlinks, non-owner files, or permissions available
to group or others.

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
- `LOCAL_CONTROL_READINESS_URL`
- `SERVICE_PROXY_ATTESTATION`

The database environment-variable name and every project-specific command are
therefore private. Treat command settings as trusted owner-controlled shell
commands. Use `local-control-prepare` to perform any locked dependency setup
before starting services; launchd deliberately does not install dependencies at
runtime.

The PostgreSQL data directory is initialized only when empty. If it contains
files without a valid cluster marker, activation stops without modifying or
removing them. Private keys remain under
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
