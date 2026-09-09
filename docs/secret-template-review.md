# Secret template review

Reviewed on 2026-09-08. The template migration, service-settings consolidation,
and shared FlakeHub authentication are deployed and verified on Linux and macOS.
Private key locations, network details, and deployment captures remain outside
this repository.

## Current representation

The repository contains 14 canonical `.age` files: nine newly encrypted scalar
fields, one newly encrypted service-settings bundle, and four existing raw
credentials. Ten configuration inputs now use public templates.

| Configuration | Representation |
| --- | --- |
| Git name and email snippets | Four private scalar fields shared with the Jujutsu template. |
| Git allowed signers | Reuses the email fields and preserves the public key and Git-only namespace restriction. |
| SSH login include | A private login value inserted into the public `User` directive. |
| Nix access tokens | Two token fields, with the shared user token also used by the Linux system. Host and home runtime ownership remain separate. |
| FlakeHub netrc | One shared login and one shared password reused by both hosts and all four reviewed machine entries. |
| Service environment | One encrypted bundle of fifteen assignments, including private variable names. The template uses a single neutral placeholder. Comments are omitted. |
| Wi-Fi, Hugging Face, and Smithsonian credentials | Four existing scalar ciphertexts retained. |

The adapter requires the replacement fields and fails evaluation if a required
ciphertext is absent. Historical `original` paths in the inventory identify
migration inputs. Each of the four evaluated plans contains zero retired
whole-configuration secret declarations.

The service assignments share one owner, access policy, consumer, and restart
action. Their bundle replaces fifteen numbered files. Two shared FlakeHub
ciphertexts replace eight redundant files after an in-memory comparison proved
all four machine entries use the same credentials. The parser rejects unequal
credentials and duplicate machine entries.

## Verification

- Canonical configurations were decrypted in memory on the machine holding the
  administrator identity. Reconstructed templates matched their original syntax
  or parsed semantics. Every replacement ciphertext was decrypted and compared
  byte for byte with its intended payload. Private keys and plaintext values
  were neither printed nor transferred to the other machine.
- All 15 secret tests and the Nix template-policy check pass. Coverage includes
  real encryption and rendering, shared-credential consistency, private service
  names and values, restrictive permissions, and missing-field rejection.
- Both complete system closures built successfully. Native macOS plans match
  the reviewed plans. Provisioning signed the required target artifacts, and
  installed system plans match the final plans on both platforms.
- System and user activation services report success. All 17 installed user
  templates, including the macOS service environment, match their runtime
  fields byte for byte. Field and template ownership, groups, and permissions
  match their activation specifications.
- Git reads identity templates, SSH configuration parses, and Jujutsu identity
  links resolve into volatile template storage on both platforms. Verification
  reads private values in memory and emits only pass/fail summaries.
- The desktop FlakeHub login service is active with a successful result. Both
  hosts use Nixd's supported token-file login interface with a protected runtime
  path. Configured substituters exclude FlakeHub Cache; this change enables no
  paid cache or subscription.

Builds used isolated source snapshots so unrelated workstation edits were not
included. The native macOS build retained existing, separate deploy-rs and Prism
Launcher package fixes for filesystem-event tests in the Darwin sandbox.
The macOS activation completed in a local terminal with App Management
permission. A temporary editor extension link was preserved privately before
restoring Home Manager ownership on Linux.

## Cleanup and review

The eleven retired whole-file ciphertexts and the 23 superseded field files
are absent from both working checkouts. Small private encrypted rollback
archives preserve their contents and the relevant signed artifacts. Archive
members were verified by hash before removing deployment staging.

Both machines' service-bundle and FlakeHub staging directories were removed,
including obsolete activation helpers, exports, build links, and duplicate
plans. Build source snapshots and authoring helpers had already been removed.
The retained private migration directory holds encrypted recovery archives,
final public plans, read-only verification helpers, and validation summaries.
Existing installed caches and system generations remain available for rollback.
No private keys were transferred and no sudo policy was changed. Live
verification passed again after cleanup.

The working-tree review compared the migration with root commit
`d0c82c0e185efa08f9e5cd605454403cb09b838a` and the separate nix-seal changes with
`f76477bd8caac37f84553df48b48dc14a1365a9f`. Staged, unstaged, and new files in
scope were included. The user's migration, privacy, consolidation, and free
FlakeHub authentication requirements supplied the acceptance criteria.

The standards review previously found a VM argument probe whose first failed
assertion could be masked by its second successful assertion. Adding `set -eu`
fixed that defect. A regression check rejects the incorrect first argument,
and the updated VM check passes. The final standards review and separate
requirements review found no remaining actionable defects.

The nix-seal checks passed Rust formatting, Clippy with warnings denied,
workspace tests, cargo-vet, and all native Linux flake checks. Cargo-vet uses
the repository's recorded exemptions; passing does not mean every dependency
is fully audited. The current root and submodule trees passed the private
terminology scan. Published history was not rewritten, and source changes
remain uncommitted.

Boot-time activation after a restart has not been exercised. These results
cover builds and completed live system and user activation.

## Template source layout

Public template text now lives in `.template` files under shared home and host
folders, with the service template in the MacBook's local configuration. Each
target explicitly selects its inventories. The generic loader lives in
`lib/secrets/templates.nix`; the central `secrets/templates.json` is retired.
See the [template locations](secrets.md#config-templates).

All ten templates and field bindings match the previous inventory exactly.
Evaluating the four target modules before and after the move produces identical
nix-seal declarations, including template store paths and runtime permissions.
The Nix secret-template check and all 16 Python tests pass, including a local
inventory authoring regression. This source reorganization requires no new
ciphertext, signed artifacts, or activation.

## Configurable ciphertext storage

nix-seal now provides target-level `secretDirectory` and
`sharedSecretDirectory` options. Scoped declarations can opt into the latter
with `shared = true`; explicit sources retain precedence. Upstream defaults
continue to use `secrets/`. The directory options reject unsafe relative paths
and leave canonical IDs and access policies unchanged.

This repository's 14 ciphertexts now live under `homes/shared/secrets`,
`hosts/shared/secrets`, and `modules/shared/secrets`. The root `secrets/`
directory is removed. File hashes match before and after relocation. Each of
the four full plans differs from the deployed plan only in source paths;
template definitions, source hashes, recipients, runtime permissions, and IDs
are unchanged.

All 24 replacement target artifacts were signed on the administrator machine
and imported into both user caches. Successful command output confirms import
into both root caches as well. The running systems retain their previous plans
until a normal rebuild. Temporary exchanges and completed import helpers were
removed after verifying private encrypted recovery archives.

The 17 Python tests and Nix template-policy check pass. Module checks cover
default and custom paths, sharing across a host and home, explicit overrides,
stable IDs and runtime paths, target-specific consumers, and unsafe directory
rejection. Rust formatting, Clippy, workspace tests, and cargo-vet also pass.
