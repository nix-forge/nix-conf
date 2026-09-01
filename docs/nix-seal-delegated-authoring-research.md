# Delegated nix-seal secret creation

## Finding

The Smithsonian setup stopped at a deliberate authorization boundary. The
desktop SSH key can receive target artifacts but is not an administrator or
recovery age identity. `nix-seal secret create` requires the latter because it
encrypts the input, decrypts the staged ciphertext to verify it, and commits it
atomically. This keeps a delivery key from replacing repository ciphertext.

The current CLI gate is in [the canonical-authoring check](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-cli/src/main.rs#L2219-L2257), and the round-trip verification requirement is in [the authoring transaction](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-authoring/src/lib.rs#L413-L470). Canonical recipients are public-plan-derived in [the policy implementation](https://github.com/nix-forge/nix-seal/blob/e1075897c428c971aa75102952e326d8e013010b/crates/nix-seal-policy/src/lib.rs#L980-L1045). Age itself separates public recipients from private identities. [age manual](https://github.com/FiloSottile/age/blob/v1.2.1/doc/age.1.ronn#L193-L282)

Giving an agent an administrator age identity would remove the immediate
blocker, but it would also let that agent decrypt every canonical source for
which it is a recipient. Allowing a direct-delivery target key to author would
have the same problem for any canonical source that includes that target. Both
are the wrong default.

## Recommended feature

Add a default-off `nix-seal secret create-delegated` command. It accepts
plaintext only on standard input and a signed, one-use create capability. The
agent receives neither an administrator age identity nor a decrypt service.
The command uses public age recipients from the plan to encrypt the new value,
then atomically creates the canonical ciphertext. It never accepts replacement
mode.

The capability must bind all of the following:

- exact secret ID and canonical repository-relative destination
- plan hash and hash of the derived recipient set
- create-only operation and a bounded plaintext byte count
- SHA-256 digest of the user-confirmed plaintext
- issued and expiry times, an opaque nonce, and a dedicated authoring-signer ID

The CLI must persist consumed nonces in a private, owner-only state directory
and reject a second use. It must derive recipients, source path, and all
limits from the pinned plan, not from capability-controlled arguments. A
separate authoring signing key prevents artifact-release authority from being
silently reused for secret creation.

## Bootstrap UX

New secrets expose a second issue: a normal plan pins the ciphertext hash, but
the hash does not exist before creation. nix-seal should provide a separate
bootstrap plan output for explicitly declared pending secrets. That output
uses a sentinel source hash, cannot drive activation or rekeying, and is valid
only for `create-delegated`. After creation, the regular plan computes the real
hash and activates normally.

This avoids temporary hand-written JSON plans and keeps a failed or abandoned
creation from affecting deployment.

## Safe workflow for agents

1. A user or a protected authoring signer grants a short-lived capability for
   one pending secret.
2. The agent pipes the supplied value directly to `create-delegated`.
3. nix-seal writes only the new canonical age file, records the consumed nonce,
   and prints redacted public metadata.
4. The regular Nix evaluation binds the new ciphertext hash. Artifact rekeying
   and normal activation remain unchanged.

This resolves first-secret bootstrapping while preserving the current rule that
an agent cannot read or replace pre-existing canonical secrets.
