# Delegated creation without an administrator age key

## Decision

Add a narrowly scoped, create-only delegation flow. Do not give an agent the
desktop target key as an authoring key, and do not copy an administrator or
recovery age identity onto the MacBook just to make first-secret setup easy.
Those choices turn a machine that can receive one runtime artifact into a
machine that can decrypt or rewrite canonical repository ciphertext.

The feature needs two pieces:

1. A public bootstrap plan for a *declared pending secret*. It can authorize
   only first creation. It cannot provision, activate, rekey, reveal, rotate,
   or replace anything.
2. A signed, short-lived capability for one bootstrap-plan secret. The
   create command encrypts stdin to the plan-derived public age recipients,
   writes one new `.age` file, and records the capability nonce. It has no age
   identity and never decrypts a canonical secret.

This is the smallest useful authority. It fixes the Smithsonian first-secret
case while leaving the present administrator/recovery gate in place for every
existing secret and every mutation.

## What the current code protects

The current design correctly separates target delivery from canonical
authoring. `ensure_canonical_authoring_identity_authorized` accepts only an
administrator or recovery recipient, even for direct delivery. The comment in
the code says why: target keys may receive an artifact but must not create or
replace repository ciphertext. [CLI gate](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-cli/src/main.rs#L2219-L2257)

`run_secret_write` derives the destination and recipients from the compiled
plan, reads stdin, and calls the transactional writer. It does not accept a
caller-selected output path or recipient list. [Secret write path](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-cli/src/main.rs#L5003-L5074)

The authoring transaction locks the repository, writes a private same-directory
temporary file, encrypts it, verifies a decrypt-and-hash round trip through an
authorized identity, then commits with `persist_noclobber` for creation. It
also rejects unsafe ancestry and destination replacement. [Authoring transaction](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-authoring/src/lib.rs#L396-L470)

The Nix bridge computes `sourceCiphertextHash` with `builtins.hashFile`. That
is why a secret that has never existed cannot appear in the ordinary compiled
plan. [Nix plan builder](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/nix/lib/default.nix#L28-L96) The desktop configuration works today because it leaves the Smithsonian
secret out entirely until its `.age` file exists. [Desktop declaration](../homes/desktop/nix-seal.nix)

Canonical recipient selection is deterministic and public. It includes the
declared administrator and recovery recipients, and adds consumer targets only
for direct delivery. [Recipient derivation](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-policy/src/lib.rs#L980-L1045)

These constraints match age's model. A recipient string encrypts, while a
private identity decrypts. An age recipient cannot be turned back into an
identity. [age manual](https://github.com/FiloSottile/age/blob/v1.2.1/doc/age.1.ronn#L193-L282)

## Capability format and signing boundary

Use a new strict `nix-seal.delegated-create-capability.v1` JSON payload inside
a signed envelope. It should have a different DSSE payload type and signature
domain from target artifacts. Do not reuse a target-artifact envelope with a
different interpretation. The manifest crate already has strict Ed25519 and
OpenSSH Ed25519 signing support, canonical JSON, key IDs, bounded envelopes,
and duplicate-signer rejection. It should expose those primitives through a
separate capability API, with a new domain string. [Manifest signing](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-manifest/src/lib.rs#L625-L708)

The payload should bind every authority decision:

```json
{
  "schema": "nix-seal.delegated-create-capability.v1",
  "operation": "create",
  "capabilityId": "base64url-256-bit-random-nonce",
  "issuerKeyId": "ed25519:...",
  "bootstrapPlanHash": "blake3-hex",
  "secretId": "ianhollow/users/ianmh/smithsonian-open-access-api-key",
  "source": "secrets/ianhollow/users/ianmh/smithsonian-open-access-api-key.age",
  "recipientSetHash": "blake3-hex",
  "plaintextSha256": "sha256-hex",
  "maxPlaintextBytes": 65536,
  "issuedAt": 0,
  "notBefore": 0,
  "expiresAt": 0
}
```

The tool must derive `source`, recipients, and the recipient-set hash from the
validated bootstrap plan. It must compare them to the signed payload. It must
never trust a source, recipient, or maximum passed alongside the capability.
Compute the recipient-set hash from an RFC 8785 canonical object containing the
sorted public recipient strings and a fixed domain prefix. The policy crate
already emits canonical JSON and domain-separated BLAKE3 plan hashes. [Canonical plan hashing](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-policy/src/lib.rs#L1475-L1482)

Use SHA-256 for the plaintext commitment because it is easy to inspect with
standard tools and the project already uses it for the committed ciphertext
binding. The writer may keep BLAKE3 for its internal stream comparison. The
capability verifier compares both the byte count and SHA-256 before making the
ciphertext visible. It never prints either digest alongside plaintext.

Introduce a separate public identity role, `authorizer`, rather than accepting
the existing `signer` role. Release artifact approval and delegated canonical
creation are different powers. The flake catalog should contain only the
authorizer public key. Its private key belongs in an explicit local file or an
explicit SSH agent reference, outside the repository and Nix store. The
existing signer implementation already refuses to infer a random SSH agent
from the environment. [Explicit agent-key handling](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-manifest/src/lib.rs#L113-L190)

The issuer should have to confirm a short capability expiry. Cap the maximum
validity in the CLI at 15 minutes. Treat a time before `notBefore`, an expired
capability, or a capability issued too far in the future as an error. The
existing artifact path already has a bounded clock-skew model, so the new
check should use the same convention rather than inventing a second one.

## Bootstrap plan and Nix UX

Add `nixSeal.secrets.<name>.pending = true`, defaulting to `false`. A pending
secret keeps the normal source-path, recipient, owner, and runtime metadata in
the module, but it is excluded from the normal plan and activation documents.
It does not make a deployment attempt to activate a missing secret.

Expose a read-only `nixSeal.bootstrapPlanFile`. It contains the same public
policy projection, but only pending secret entries get the exact sentinel
`sourceCiphertextHash` of 64 zeroes. The bootstrap schema must be distinct,
for example `nix-seal.bootstrap-create-plan.v1`. Normal plan parsing must reject
that schema. Bootstrap parsing must reject every secret except a pending one
with the sentinel hash. It cannot be accepted by `check --deep`, `provision`,
`rekey`, activation, or artifact commands.

When creation succeeds, the user changes `pending = true` to the normal
declaration. The ordinary `planFile` then calls `builtins.hashFile` over the
new ciphertext as it does now. No plaintext goes into the Nix store. This is a
small, explicit configuration change and is safer than trying to mutate Nix
configuration from a secret-writing command.

For the current desktop module, the ergonomics become:

```nix
nixSeal.secrets.smithsonian-open-access-api-key = {
  pending = true;
  owner = "ianmh";
  group = "ianmh";
  mode = "0400";
};
```

The agent can read the public bootstrap plan and request a capability. It still
cannot activate or reveal the secret. After creation, a normal configuration
evaluation changes `pending` to `false`, provisions a target artifact, and
activates it.

The best interactive flow is deliberately short:

```console
nix-seal secret delegate prepare --bootstrap-plan "$BOOTSTRAP_PLAN" \
  --secret ianhollow/users/ianmh/smithsonian-open-access-api-key --read-from-tty \
  > request.json
nix-seal secret delegate issue --request request.json \
  --authorizer-key "$AUTHORING_KEY" > capability.json
nix-seal secret create-delegated --bootstrap-plan "$BOOTSTRAP_PLAN" \
  --capability capability.json --spent-store .nix-seal/delegations/v1 \
  --read-from-tty
```

`prepare` reads the value from a verified controlling terminal with echo
disabled and produces a public SHA-256 commitment. `issue` signs only that
commitment and the public plan bindings. `create-delegated` reads the same
value from the terminal, so it cannot accidentally use the wrong clipboard
entry. For noninteractive automation, accept stdin only when the caller passes
an explicit `--stdin` flag. Never accept plaintext in argv, environment, JSON,
logs, shell history, or a Nix expression.

One practical refinement is a single `delegate create --interactive` command
that runs the three steps locally and asks the authorizer key to sign after it
shows the secret ID, destination, recipients, byte count, and expiry. Keep the
separate commands too. They make audit and agent-assisted handoff easier.

## Replay, revocation, and crash behavior

The capability is create-only and tied to one nonexistent destination. That
alone prevents a replay from changing an existing secret. Still record the
nonce so a second attempt fails clearly rather than merely failing because the
file exists.

Store nonce records under the repository's ignored, owner-only
`.nix-seal/delegations/v1/` directory. Use a path derived from a hash of the
capability ID, not the raw ID. Each record includes the signed capability hash,
secret ID, source, state, ciphertext hash, and timestamps. It contains no
plaintext. Reuse the authoring crate's repository lock, private-directory
checks, no-follow opens, same-device temporary files, rename, and directory
`fsync` patterns. [Private transaction support](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-authoring/src/lib.rs#L1056-L1225)

The transaction should stage the new ciphertext and a private `committed`
nonce receipt in one all-or-recover batch. The current combined batch API needs
one extension: allow a create-only encrypted write that has no verification
identity, while retaining the same path checks, output bounds, ciphertext
header validation, and durability handling. `age` encryption succeeds only
after it has parsed every derived recipient. There is no way to do the current
decrypt round trip without giving the delegate a decryption identity, which
would defeat the feature.

If the batch reports durability-unknown, do not retry automatically. `nix-seal
secret delegate recover` should inspect the one source path and the one nonce
receipt with no-follow checks, report whether the result is committed, rolled
back, or unknown, and require a new capability if the result cannot be proved.
That is blunt, but it is better than treating a half-finished creation as safe.

Immediate global revocation is not realistic for an offline bearer capability
unless the create machine can obtain a fresh signed revocation list. Make this
clear in the manual. Short expiry, a one-use receipt, create-only writes, and
deleting an unneeded capability file are the default controls. A later online
issuer can add signed revocation lists, but that should not block the local
first-secret workflow.

## Exact implementation map

| Area | Change |
|---|---|
| `crates/nix-seal-core/src/lib.rs` | Add `IdentityKind::Authorizer` and strict bootstrap-plan and capability public types, or place the latter in a small dedicated `nix-seal-delegation` crate. |
| `crates/nix-seal-policy/src/lib.rs` | Validate the bootstrap schema, derive a one-secret create policy, expose deterministic recipient-set hashing, and keep normal plan APIs incapable of consuming a bootstrap plan. |
| `crates/nix-seal-manifest/src/lib.rs` | Add separate capability sign/verify functions with a new payload type and domain string. Keep artifact envelope verification unchanged. |
| `crates/nix-seal-authoring/src/lib.rs` | Add a bounded create-only, no-decrypt transaction and commit the encrypted secret plus private nonce receipt together. Do not weaken `write_secret`. |
| `crates/nix-seal-cli/src/main.rs` | Add `secret delegate prepare`, `issue`, `create`, and `recover`, with strict argument structs and redacted output. Keep `secret create` on the current administrator/recovery path. |
| `crates/nix-seal-cli/tests/authoring.rs` | Add end-to-end bootstrap, delegated-create, post-create ordinary-plan, and administrator-rekey tests. This is already where plan-directed create/reveal behavior is covered. [Existing fixture](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-cli/tests/authoring.rs#L1-L145) |
| `nix/lib/default.nix` | Add a closed `mkBootstrapCreatePlan` that writes the sentinel only for pending secrets. Leave `mkPlan` and `builtins.hashFile` unchanged for normal plans. |
| `nix/modules/flake-module.nix` | Allow `authorizer` in public catalog identities and document that it signs delegated creation capabilities only. |
| `nix/modules/shared.nix` | Add `pending`, project pending items into `bootstrapPlanFile`, exclude them from activation and normal `planFile`, and add assertions that prevent mixed pending and normal states. |
| `nix/tests/module-evaluation.nix` | Verify the pending secret has a bootstrap entry with a sentinel hash, has no normal-plan or activation entry, and turns into a normal hashed entry once the source exists. |
| `SPEC.md`, `THREAT_MODEL.md`, `docs/runbooks.md`, `docs/nix-seal.1` | Specify the capability schema, expiry, signer separation, non-replacement guarantee, recovery states, and the fact that delegated encryption does not perform a decrypt round trip. |

## Required tests

Security tests matter more here than happy-path polish.

- A valid capability creates exactly one absent source without an age identity. An administrator and a recovery identity can decrypt the result afterward.
- Existing source, symlinked parent, hard-linked destination, traversal, target-key identity, `--replace`, and a second capability use all fail without changing the source.
- A changed secret ID, source, bootstrap-plan hash, recipient-set hash, issuer, signature algorithm, signature domain, plaintext SHA-256, byte count, not-before time, or expiry time fails.
- A release artifact signer cannot issue a capability. An authorizer cannot approve a target artifact.
- Unknown JSON fields, duplicate signer IDs, noncanonical payloads, oversized capability files, malformed base64, and clock-skew attacks fail before any plaintext is read.
- Two simultaneous creators holding the same capability leave one ciphertext and one receipt, or a provable rolled-back state. No test may accept two canonical writes.
- A simulated crash or directory-sync failure returns durability-unknown and `delegate recover` never guesses that the source is safe.
- The Nix module never calls `hashFile` for a pending source. The ordinary plan and activation reject bootstrap plans. A re-evaluation after creation produces the normal ciphertext hash and permits standard provisioning.
- CLI stdout, stderr, JSON output, temporary files, and test failures contain no value canary.

## Why this is better than using the desktop SSH key

The desktop's `~/.ssh/id_ed25519` can already decrypt target-delivery material.
It should not gain permission to create canonical content that every future
target may trust. A delegated capability has a much smaller blast radius: one
name, one path, one public recipient set, one committed value, one short time
window, and no replacement operation. It also gives an agent a clean UX. The
agent can complete the work after the user approves a single, legible request,
without ever holding the administrator or recovery age identity.
