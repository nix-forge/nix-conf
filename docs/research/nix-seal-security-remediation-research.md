# Resolving remaining secret-management security issues

Reviewed: 2026-11-07. Scope: the current `nix-seal` dependency graph, existing
generator outputs. AudioMuse follow-up and Git history cleanup are excluded. This is remediation research, not approval of an unreviewed
cryptographic dependency change.

## Answer

Remove unsupported native tagged recipients from released age 0.12.1, and pin
only i18n-config to its merged upstream parser replacement. Require explicit
repair of ambiguous legacy generator output sets. Isolate RSA in an independently resolved, explicitly selected compatibility
build; retain its offline exception until the actual OAEP path has reviewed
closure.

| Concern | Selected implementation | Completion condition |
| --- | --- | --- |
| Affected `crypto-bigint` | Vendor released age 0.12.1 and remove unsupported `tag`/`tagpq` surface and dependencies. | Both workspace graphs exclude the affected packages; supported paths and native package checks pass. |
| Unmaintained `basic-toml` | Pin only i18n-config to the merged parser replacement. | Complete graph excludes basic-toml; parser regression, provenance and dependency gates pass. |
| RSA timing exception | Separate age SSH features and build RSA migration in an independent workspace. | Normal and fuzz graphs exclude RSA; normal Ed25519 and opt-in RSA migration pass. |
| Legacy generator associations | Mark new state and reject ambiguous older output sets before reuse. | Red/green regression, safe small sets and marked-state compatibility pass. |

## Remove unsupported recipient dependencies

Released age 0.12.1 activates P-256 through its native tagged recipients and
HPKE. That branch reaches elliptic-curve 0.13.8 and crypto-bigint 0.5.5; it cannot
upgrade through a compatible lockfile-only change. Nix-seal's constructors expose
X25519, plugins and SSH compatibility, not native tagged recipients. Removing all
SSH support would not remove this P-256 branch and would break Ed25519 workflows.
[Published manifest][published-age], [local constructors][crypto-boundary],
[arithmetic advisory][bigint-advisory].

The selected patch removes those two recipient implementations, their exports,
recipient-file parser branches and four direct dependencies. Retained supported
cryptographic implementations are unchanged from the released archive.
Released age-core retains HPKE's allocation-only surface without P-256. Its
upstream development dependencies must not become application workspace members.
The [source inventory][age-provenance] records original and modified hashes;
offline CI checks every retained file and rejects additions and symlinks. This
is a maintained local patch, not a claim that the published crate has changed.
[Decision][dependency-adr], [patch description][vendor-note].

An alternative unreleased age revision,
`b5b68c4f4f7ea5c368bc060f6fe0237549c3a13f`, adopts a new cryptographic dependency
generation. Disposable probes compiled and passed the 13 crypto tests with
patched arithmetic. The full resolved delta, however, introduced 53 crate
versions and changes to arithmetic and cipher implementations. Source review
also found that new ChaCha20-Poly1305 makes key zeroization optional, whereas the
older implementation performs it unconditionally; the proposed age manifest
did not request that feature. That requires review before adoption. No deployment
audit is claimed for the abandoned broad candidate.
[Age manifest][age-workspace], [old cipher][old-chacha],
[new cipher manifest][new-chacha].

Both the root and independent fuzz workspaces require the same source overrides
and separately resolved lockfiles. Replace the local age patch after a supported
upstream release passes the same security and compatibility checks. Do not add
advisory ignores or bootstrap exemptions to accommodate either replacement.

## Replace only the localization configuration parser

The two build-time paths are age → `i18n-embed-fl` → `i18n-config`, and age →
`i18n-embed` → `i18n-embed-impl` → `i18n-config`. They select published
`i18n-config 0.4.8`, which uses `basic-toml 0.1.10`. This advisory is a maintenance
notice, not evidence of a newly demonstrated parser exploit.
[Advisory][toml-advisory].

The parser replacement is already merged in cargo-i18n
[PR #176][i18n-pr]. Pin only `i18n-config` at merge commit
`2ce7b1dfe9a8cc224288bf50cbc2a67a6de863c4`, leaving released localization consumers
in place. That configuration crate has no dependency on the other cargo-i18n
workspace packages. The upstream patch uses maintained `toml`, changes the
parser error payload, and includes some public API cleanup; compatibility must
therefore be demonstrated rather than inferred from its unchanged 0.4.8 version.
[Pinned configuration source][i18n-source].

At the nix-seal workspace root, the intended source override is:

```toml
[patch.crates-io]
i18n-config = { git = "https://github.com/kellpossible/cargo-i18n", rev = "2ce7b1dfe9a8cc224288bf50cbc2a67a6de863c4" }
```

Cargo supports this transitive override at the top-level workspace. Confirm the
lockfile selects the replacement and no `basic-toml` remains. Keep the existing
compatible maintained `toml` resolution to separate parser removal from an
unrelated parser update. [Cargo patch semantics][cargo-patch].

A smaller vendored backport needs one dependency change and three Rust reference
changes: the error payload and two deserialization calls. It avoids unrelated
upstream cleanup but makes this project responsible for a derivative crate.
Prefer the upstream pin unless its scoped compatibility tests fail. Preserve
licenses, source provenance and an exit condition for either temporary choice.

Test the actual age configuration and Cargo manifest, compilation of both
released macro consumers, missing required fields, invalid language identifiers,
wrong types, duplicate keys and malformed input. Maintained TOML accepts newer
syntax and has different diagnostics; retain useful failures without demanding
byte-identical old error text. Parser recursion and additional configuration
defaults need coverage before release beyond the initial feasibility probe.

## Isolate RSA compatibility

RustSec still records `patched = []`. Its explicit affected-version statement
predates recent upstream work, so neither the advisory nor a closed upstream
issue alone establishes closure for this application. [Advisory][rsa-advisory].

RustCrypto merged [PR 749][rsa-implicit] on November 1, introducing PKCS#1 v1.5
implicit rejection and reporting checkct/BINSEC analysis. Version
[0.10.0-rc.22][rsa-release] was tagged on November 7 at
`e0ba49d53015e501ceab172b720b16e86e48e0f5`. Age's SSH decryption uses **blinded
OAEP-SHA256**, not PKCS#1 v1.5 encryption padding. Age already explicitly requests
blinding and disables RSA defaults, so default-path blinding alone adds no
protection to that call. [Age SSH source][age-ssh], [OAEP source][rsa-oaep].

The selected implementation separates age’s existing SSH feature surface.
`ssh` retains Ed25519; only the independently resolved `legacy/` workspace
selects `ssh-rsa`. Its `nix-seal-legacy` package reuses the canonical CLI source
and existing migration handlers, with its own lockfile, source filter and
advisory policy. Normal builds report an actionable error for RSA sources.
Metadata inventory uses the existing allocation-only SSH wire parser with the
released modulus and exponent bounds. This preserves migration without changing
the cryptographic implementation or adding a subprocess decryption backend.
[Isolation decision](../../nix-seal/docs/adr/0031-isolated-rsa-migration-build.md).

OSV configuration is discovered beside each lockfile. An explicit global
`--config` would override nested policies and widen the legacy exception; CI
therefore uses recursive discovery without that override.
[OSV configuration](https://github.com/google/osv-scanner/blob/main/docs/configuration.md).

For eventual removal of the compatibility exception, investigate a separate
frozen upstream candidate:

1. Review the complete age/RSA adaptation to rc.22 or a supported successor. The
   inspected age candidate pins rc.18 exactly, requiring a reviewed source
   change rather than a lockfile update. Review arithmetic, cipher key zeroization
   and PKCS#1 version coupling together.
2. Trace OAEP padding, modular arithmetic, errors and caller diagnostics. Obtain
   upstream clarification and timing evidence for that exact path before
   removing the exception. A PKCS#1 v1.5 claim does not establish OAEP closure.
3. Test existing migration keys and malformed inputs. The new private-key importer
   constrains prime widths unless a separate capability is enabled; a narrower
   accepted key set can break legacy migration. Preserve normal RSA rejection
   and the existing no-prompt boundary. [Private-key source][rsa-private],
   [ADR 0009][rsa-adr].
4. If OAEP closure cannot be established, pursue upstream SSH feature separation:
   retain normal Ed25519 support and put RSA into a separately selected offline
   migration tool. Resolve and build them independently. A runtime flag or
   second binary in a unified feature graph does not remove the dependency.
   Avoid a home-grown cryptographic backend.

Until one path passes review, retain the existing narrow exception and offline,
non-interactive migration restrictions. No network-facing RSA API is authorized.

## Existing generator output repair

The corrected loader now reads each output class in numeric declaration order.
An affected run has **at least 11 secret outputs or at least 11 public outputs**;
ten of each is unaffected by this ordering error. Previously, twelve outputs
were read as `0, 1, 10, 11, 2, ...`, so declared output 2 received output 10's
value, encrypted for output 2's recipients. Secret and public output vectors
were separate; the ordering bug does not itself move a secret into the public
output directory. [Loader and transaction](../../nix-seal/crates/nix-seal-cli/src/main.rs).

The current host/home and selected module source contains no external secret
generator declarations, and this checkout has no local generator validation
state. Header-only inspection of 100 tracked age files found X25519 and GREASE
stanzas, with no SSH RSA or P-256 stanzas. These are current observations, not
proof about previous runs or about which plaintext belongs in each ciphertext.
No decryption, identity loading or generator execution was performed.

For any older affected run, preserve a private backup and reconstruct the
lexical-to-numeric permutation separately for secret and public outputs. Compare
each value's intended recipient set with the set it actually received. Repair
associations transactionally with a corrected binary and verify dependent
services and public/private key pairs. If extra recipients could decrypt a
value, rotate or revoke it; re-encryption alone cannot undo that exposure. Avoid
blind regeneration of externally assigned credentials or keys.

Existing validation state could return `unchanged` after an upgrade, preserving
old associations. New state records `declaration-numeric-v1`; existing unmarked
large external sets stop before reuse or implicit replacement. Historical state
lists are checked even after validation is removed, lists shrink or the generator
switches to a builtin. Unknown markers fail closed. Small legacy sets and marked
state retain their existing behavior. Reading and serialization enforce the same
64 KiB limit before publication. This local marker is under the invoking user's
control, not an authenticated historical attestation.
[Generator decision](../../nix-seal/docs/adr/0005-plugins-generators.md).

## Integration, verification and rollback

Implementation belongs in the nix-seal submodule. The selected dependency
boundary is documented in ADR 0030.
Update the root gitlink only after the submodule's reviewed change is committed.
Preserve the other task's staged and unstaged changes throughout.

For Git dependencies, retain full revisions in Cargo.lock, narrowly allow their
repositories in cargo-deny, and add verified `cargoLock.outputHashes` for the
Nix fetches. Cargo-vet must review the Git-qualified deltas; an exemption for the
same registry version does not audit different source. Local/path vendoring also
requires explicit source review because vet cannot fingerprint arbitrary local
modifications. [Vet source treatment][vet-first],
[Nix package](../../nix-seal/flake/production.nix).

Vendoring additionally requires updating the explicit
[Rust source filter](../../nix-seal/flake/rust-source.nix) and its behavioral
regression test so vendor code, licenses and fixtures enter native builds. Keep
advisories enabled and remove obsolete exemptions only after their packages
disappear. Prefer a narrow patch record with provenance and an upstream release
exit condition over a permanently hidden dependency fork.

Before release, run the submodule's complete locked format/check/Clippy/test,
audit/deny/vet and Nix checks. Include X25519, OpenSSH Ed25519, explicit RSA
migration, plugins, passphrase recovery, invalid ciphertext and cross-tool
interoperability. Run native Linux and Darwin package checks, source-boundary
tests, and the affected runtime VM. Check strict linting and the actual MSRV;
successful compilation with a newer compiler does not establish either.

Dependency rollback is a source/lockfile reversion, with the old security release
block restored. Do not rewrite ciphertext merely to roll back a library pin.
Credential rotation and corrected generator mappings have separate operational
rollback requirements; reverting code does not restore revoked credentials.

## Validation and limits

Primary source manifests, immutable archives, registry status, advisories and
local callers were inspected. Disposable broad-upgrade probes passed a workspace
compile check, all 13 crypto tests, two additional parser tests and the advisory
subcheck using only the existing RSA exception. They establish feasibility, not
acceptance of that abandoned dependency migration.

The old generator implementation passed the existing validation-state control
and failed the new large-legacy-output regression, confirming unsafe reuse.
The narrow dependency candidate resolved both workspaces without crypto-bigint,
P-256 or basic-toml. A native macOS diagnostic then failed in its job supervisor
during compilation and left an unresolved drainage receipt. No remaining matching
process was observed, but that does not replace authoritative cleanup evidence.
This attempt is not a passing test or package build.

On native x86 Linux, the frozen narrow candidate passed workspace format, check,
strict Clippy, all 225 tests, the independent fuzz compile check, cargo-deny
(advisories, duplicates, licenses and sources), cargo-vet and cargo-audit using
only the pre-existing RSA exception. Cross-tool and CCTV tests were required,
not silently skipped. Public vendored fixtures initially triggered Gitleaks;
exact reviewed-value/path exceptions now pass both the staged scan and the
frozen-tree scan. Canary tests still detect unknown credentials at those paths.
All staged vendor blobs match their recorded hashes, including CRLF fixtures.

Complete native Nix checks remain queued behind another task's active workload.
The macOS supervisor failure still prevents a completed native Darwin result.
These remain release gates; a queue ID or source inspection is not acceptance.
No service activation, secret rotation, commit or history rewrite occurred.
Maintainer review remains necessary before release.

[bigint-advisory]: https://rustsec.org/advisories/RUSTSEC-2026-0387
[age-workspace]: https://github.com/str4d/rage/blob/b5b68c4f4f7ea5c368bc060f6fe0237549c3a13f/Cargo.toml
[toml-advisory]: https://rustsec.org/advisories/RUSTSEC-2026-0374.html
[i18n-pr]: https://github.com/kellpossible/cargo-i18n/pull/176
[i18n-source]: https://github.com/kellpossible/cargo-i18n/blob/2ce7b1dfe9a8cc224288bf50cbc2a67a6de863c4/i18n-config/src/lib.rs
[cargo-patch]: https://doc.rust-lang.org/cargo/reference/overriding-dependencies.html
[rsa-advisory]: https://rustsec.org/advisories/RUSTSEC-2023-0071.html
[vet-first]: https://github.com/mozilla/cargo-vet/blob/v0.10.2/book/src/first-party-code.md

[published-age]: https://docs.rs/crate/age/0.12.1/source/Cargo.toml
[crypto-boundary]: ../../nix-seal/crates/nix-seal-crypto/src/lib.rs
[age-provenance]: ../../nix-seal/security/age-source.json
[dependency-adr]: ../../nix-seal/docs/adr/0030-dependency-surface-remediation.md
[vendor-note]: ../../nix-seal/vendor/README.md
[old-chacha]: https://docs.rs/crate/chacha20poly1305/0.10.1/source/src/lib.rs
[new-chacha]: https://docs.rs/crate/chacha20poly1305/0.11.0/source/Cargo.toml
[rsa-implicit]: https://github.com/RustCrypto/RSA/pull/749
[rsa-release]: https://github.com/RustCrypto/RSA/releases/tag/v0.10.0-rc.22
[age-ssh]: https://github.com/str4d/rage/blob/b5b68c4f4f7ea5c368bc060f6fe0237549c3a13f/age/src/ssh/identity.rs
[rsa-oaep]: https://github.com/RustCrypto/RSA/blob/e0ba49d53015e501ceab172b720b16e86e48e0f5/src/oaep.rs
[rsa-private]: https://github.com/RustCrypto/RSA/blob/e0ba49d53015e501ceab172b720b16e86e48e0f5/src/private_key.rs
[rsa-adr]: ../../nix-seal/docs/adr/0009-ssh-migration-compatibility.md
