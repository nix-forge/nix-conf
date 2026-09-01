# Private local services

This module provides a small private local service set: a database,
an API, a background worker, a web process, and an optional authenticated
listener. Runtime values remain in an owner-only environment file; the public
configuration contains only generic service logic and immutable tool identities.

The Home Manager module is local to the MacBook profile at
`homes/macbook-pro-m4/local/local-control.nix`. Its implementation-only helper
functions and C source live beside that profile under
`homes/macbook-pro-m4/support/local-control/`; they are deliberately not part
of the repository-wide `lib` API.

Runtime state is stored under `~/.local/state/local-control` with owner-only
permissions. The environment file is
`~/.local/state/local-control/environment`, outside this repository. A fresh
activation creates the private state directories and any missing generated
identity files safely. A missing environment file is allowed: guarded services
remain stopped until the owner supplies it. Existing unsafe files, directories,
or generated identities fail closed. Existing owner-owned regular service logs
are safely tightened to mode `0600`; symlinks, foreign-owned files, and special
files still fail closed.

The service environment file is a strict line-oriented file. On the MacBook
host it is `~/.local/state/local-control/service-environment`. Blank lines and lines
beginning with `#` are ignored; every other line is one `NAME=VALUE` record.
Values are not evaluated as shell syntax, duplicate names are rejected, carriage
returns are rejected, and names outside this list are rejected:

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

When the optional listener is enabled, `SERVICE_PROXY_ATTESTATION` is also
required. It is rejected when that listener is disabled. Required settings must
be non-empty. The database variable name must be a valid shell identifier.

Run `local-control-prepare` after changing the checkout, commands, or
preparation input. It runs the owner-selected preparation command and writes an
owner-only proof. The proof binds the committed Git revision, a descriptor-bound
snapshot of the complete source tree, the canonical environment snapshot, the
preparation input, and the immutable runtime identities. Symlinks, special
files, non-root checkouts, changing inputs, unsupported records, and unverifiable
state fail closed. Raw setting values are not written to the proof.

The service guards require a current proof before starting. The database service
is independently guarded because the other services wait for it. Its data and
socket directories are checked by descriptor before a process is started, and a
new data directory is initialized only when it is empty. The optional listener
keeps its identity files descriptor-bound while starting. Generated files are
created with exclusive or atomic operations; a pathname-only fallback is not
used.

Use `local-control-restart` after preparation, and `local-control-status` to
inspect readiness and listeners. These commands do not create dependencies or
install packages at runtime.
