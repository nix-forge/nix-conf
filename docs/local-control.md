# Local control services and Windows development VM

This Home Manager configuration runs a private local application stack on macOS
and provides host-only SSH access to a Windows development VM.

## Local application stack

`homes/macbook-pro-m4/local/local-control.nix` manages PostgreSQL, an API, a
background worker, a dashboard development server, and an mTLS reverse proxy
through launchd. The public configuration uses only generic service names and
expects the private checkout to be available at
`~/Developer/personal/workspace-service`. Activate it with:

```bash
just home-switch ianmh@macbook-pro-m4
```

Runtime state is stored under `~/.local/state/local-control` with owner-only
permissions. PostgreSQL, the browser API, and the dashboard bind to loopback.
The reverse proxy binds only to the VMware host-only interface and requires a
client certificate before forwarding requests.

The private environment file is
`~/.local/state/local-control/environment`; it is intentionally outside this
repository and must be created by the private application checkout before
activation. Private keys remain under `~/.local/state/local-control/pki` and
are not committed to this repository.
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
