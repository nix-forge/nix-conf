# Add secrets after the starter works

The public starter has no secret manager. That keeps the first build independent
of personal credentials and lets you choose a provider when you have a concrete
secret to deliver.

Never put a plaintext credential in a Nix expression. Nix source and build outputs
can enter the readable Nix store. Use placeholders in documentation and keep
private keys outside the repository and store.

## Choose the workflow you need

| Project | What to examine before choosing |
| --- | --- |
| [sops-nix](https://github.com/Mic92/sops-nix) | Structured SOPS files, age/GPG or external key management, activation and platform modules |
| [agenix](https://github.com/ryantm/agenix) | File-based age encryption, recipient management, and deployment workflow |
| [nix-seal](https://github.com/nix-forge/nix-seal) | Public policy plans, signed target artifacts, offline provisioning, runtime storage, and current release readiness |

These are different authoring and delivery workflows. This table is not a
security ranking or an interoperability guarantee. Follow each project's current
platform and recovery documentation.

## nix-seal in this repository

The personal hosts use nix-seal. Its README states that it is pre-release and
has not received the independent audit required before production use. Keep that
status visible when evaluating it. See its
[security status](https://github.com/nix-forge/nix-seal#security-status),
[authoring guide](https://github.com/nix-forge/nix-seal/blob/main/docs/nix-authoring.md),
and [recovery runbooks](https://github.com/nix-forge/nix-seal/blob/main/docs/runbooks.md).

The complete home profiles rely on host-managed runtime storage, so they cannot
be activated as standalone replacements for the tutorial home. Review the
[root secret workflow](https://github.com/nix-forge/nix-conf/blob/main/docs/secrets.md)
when working on those hosts.

Before adopting any provider, practice creating a disposable value, delivering it,
rotating access, and recovering after losing a key. An agent test does not replace
an independent audit or a recovery drill using your actual backup process.
