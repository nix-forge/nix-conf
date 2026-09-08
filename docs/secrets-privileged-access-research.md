# Privileged access for secret template migration

Reviewed 2026-09-07 against the local nix-seal checkout at
`dc557a2baa833a9f994f7e11b156a76e2c029bbf`. This review used public configuration
and source code. It did not read private identities or plaintext secret files,
invoke sudo, or change authentication policy.

Keep the current sudo policy. Prepare and verify the public templates as the
ordinary user. If extracting existing host-owned configurations requires root,
run one reviewed, finite migration helper with a single sudo invocation. That
process can finish its bounded work after the authentication timestamp expires.
It should emit ciphertext and redacted results only. A persistent root shell,
passwordless interpreter, or general command broker would grant much more
authority than this migration needs.

## What already works without sudo

Repository inventory, template edits, Nix evaluation, and public plan validation
need no privileged access. Templates contain placeholders; nix-seal substitutes
values into private runtime generations during activation. Their ownership,
permissions, and atomic switching follow the ordinary secret lifecycle.
[Runtime template implementation](../nix-seal/README.md#runtime-templates)

Canonical secret creation and `secret batch` require an authorized administrator
or recovery age identity, but do not inherently require Unix root. The identity
must already be available to the operator. Running as root does not supply a
missing age identity or make a target identity an authorized authoring identity.
Batch extraction accepts public field mappings and structured stdin and commits
the resulting ciphertext files together.
[Authoring checks and batch implementation](../nix-seal/crates/nix-seal-cli/src/main.rs)

The catalog already declares a dedicated authorizer. Current nix-seal implements
`secret bootstrap complete` and delegated creation for absent canonical files.
These operations need authorizer signing authority, not an administrator age
identity. Delegated capabilities expire within 15 minutes and permit one
creation. They cannot reveal old configurations, replace existing ciphertext,
rekey, provision, or activate. Therefore they can help create extracted fields
only after an authorized process obtains those fields. They do not solve access
to an unreadable original configuration.
[Catalog](../flake.nix), [accepted delegation design](../nix-seal/docs/adr/0014-delegated-pending-secret-creation.md)

The earlier delegated-authoring research documents describe the proposal before
implementation. Use the current CLI and accepted ADR for command behavior.

## Why repeated sudo prompts occur

This repository configures a five-minute, per-terminal sudo cache, sanitized
environment, and password-required administration. It deliberately disables
SSH-agent authentication for desktop sudo. An authentication in a separate
terminal cannot be assumed to authorize an agent's process. Keep this separation;
do not change to a global or indefinite cache for convenience.
[Shared policy](../modules/nixos/security/sudo.nix),
[desktop policy](../hosts/nixos/desktop/local/security-sudo.nix),
[sudo's upstream timestamp documentation](https://github.com/sudo-project/sudo/blob/main/docs/sudoers.mdoc.in)

When checking already-authorized execution, `sudo -n` fails immediately if a
password is required. It neither opens a password prompt nor obtains a grant.
Do not route a password through chat, command arguments, environment variables,
or an agent-controlled askpass program.
[Upstream sudo command manual](https://github.com/sudo-project/sudo/blob/main/docs/sudo.mdoc.in)

## A single privileged migration, if needed

Prepare a helper whose public inputs fix the exact source files, expected source
ciphertext hashes, destination IDs, recipients, and transformations. Build its
code and dependencies before elevation. Use immutable executable paths and a
reviewed plan snapshot; do not execute a writable checkout script as root or
accept arbitrary shell commands, editors, output paths, or recipient overrides.

The helper should read only the declared originals, parse them inside the
process, create the new encrypted fields, and compare rendered output with the
original before reporting success. Failures should identify the operation or
field without printing values or parser excerpts. Keep originals until
verification and deployment succeed. Restrict any temporary workspace to its
owner, disable tracing and core dumps, and remove temporary plaintext on exit.
Keep ordinary event logging; plaintext must never reach stdout, stderr, or sudo
I/O recordings. These are recommendations for the migration helper, not claims
that nix-seal already provides a general migration command.

If an isolated systemd job is warranted, use a fixed unit with `LoadCredential=`
for an already-present root-owned identity, `UMask=0077`, `LimitCORE=0`, restricted
filesystem writes, and no network access. `SetCredential=` literal values are
visible through IPC and are unsuitable for secrets. `Type=oneshot` needs
`TimeoutStartSec=` for a bound; `RuntimeMaxSec=` does not limit oneshot startup.
The unit must still pin its executable and permitted operations. Systemd
credentials control delivery, not the authority of the receiving program.
[Upstream execution settings](https://github.com/systemd/systemd/blob/main/man/systemd.exec.xml),
[upstream service timeouts](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml)

For deployment, the repository already authorizes the MacBook deployment key
for restricted root SSH on desktop. The configuration correctly treats that key
as root-equivalent. Use the existing `just desktop-build` or
`just desktop-deploy` workflows from another host, and build the complete desktop
closure on desktop. This does not create age authoring authority or justify a
new passwordless sudo rule.
[Deployment credential policy](../hosts/nixos/desktop/local/system.nix),
[deployment recipes](../justfile)

## Checked implementation

The local migration helper validates reconstruction before any batch authoring.
Git configurations are compared using Git's parser; the other supported formats
are compared with their accepted whitespace and quoting rules. The Git identity
also passes a TOML round trip before it can become the Jujutsu template. Every
placeholder must resolve, and unexpected diagnostics remain redacted. Encrypted
scalar verification still follows authoring, and originals remain available.

Both Jujutsu configurations use one fallback writer that replaces a template
symlink atomically with a private regular file. It never follows the old link
into a nix-seal generation. Synthetic tests cover live and dangling links,
Unicode/quoted names, malformed templates, and rejection before batch authoring.
The desktop contract tests whole-file and field/template declarations, including
negative controls for changed ownership, permissions, and canonical sources.

Run `python3 tests/secrets/test_secret_templates.py` for synthetic Python checks,
or `nix build --no-link .#checks.x86_64-linux.secret-templates` for those checks
plus Nix policy evaluation. These checks use no real secret values or identities
and do not perform migration, provisioning, or activation. The helper is an
ordinary-user authoring tool; it is not an immutable privileged migration unit.
