# Would SecretSpec benefit nix-conf?

Reviewed: 2026-10-16. Scope: SecretSpec v0.21.1, released 2026-09-27,
commit `5a8927d2b800c604fee72970ffbd137c57820fd5`, compared with the current
nix-conf working tree and its local nix-seal integration. The latest stable
release was checked through [GitHub Releases](https://github.com/cachix/secretspec/releases/tag/v0.21.1).

## Answer

Keep nix-seal as the machine-configuration secret authority. SecretSpec could
benefit an application development workflow that needs the same declared secret
interface across local keyrings, CI, and remote providers. There is insufficient
benefit to add it to this repository's default shell or replace its host and home
secret lifecycle today.

This is a fit assessment, not a claim that the incumbent is audited or safer in
all respects. nix-seal explicitly describes itself as pre-release, unaudited,
and unsuitable for production secrets in its [README](../../nix-seal/README.md)
and [security policy](../../nix-seal/SECURITY.md). Its documented controls explain
why replacing it requires careful parity work; they do not independently prove
its implementation secure.

## Findings and sources

### The repository already solves most of the infrastructure problem

The [current workflow](../secrets.md) uses administrator-encrypted canonical
ciphertext, target rekeying, signed artifacts, public policy plans, protected
runtime files, and readiness checks before activation. Host and home secrets
have separate runtime ownership. Public templates render private configuration
without putting plaintext into Nix expressions or store outputs. Recovery and
application credential rotation have explicit [runbooks](../../nix-seal/docs/runbooks.md).

There are already consumers that avoid exporting secret values into the general
shell: the [Hugging Face module](../../modules/home/cli/hf.nix) exports a token
file path, while [service configuration](../../hosts/nixos/desktop/local/homelab/actual.nix)
uses systemd `LoadCredential`. Some applications still require protected
environment files; keeping those uses narrow remains worthwhile.

The [development shell](../../flake/dev/shell.nix) uses `mkShellNoCC`, and
[direnv](../../.envrc) loads the flake environment. Neither declares a SecretSpec
workflow. The desktop already selects the
[GNOME Keyring integration](../../modules/nixos/security/keyring.nix).
These are working-tree observations, not runtime verification.

### What SecretSpec would add

SecretSpec separates application requirements from storage providers. Profiles,
scopes, provider routing, required-value validation, and SDKs let an application
keep one logical contract while developers and CI supply values differently.
That can reduce ad hoc dotenv handling and custom provider-specific scripts.
See the [released configuration documentation](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/docs/src/content/docs/reference/configuration.mdx).

| Use in this project | Potential benefit | Assessment |
| --- | --- | --- |
| Host/home activation, Wi-Fi, daemon credentials, private templates | A common provider interface | Low immediate benefit; significant policy and lifecycle integration work |
| A separate application developed on several machines and in CI | One declaration, provider-specific storage, explicit per-command delivery | Strongest candidate for a limited trial |
| A custom application that already receives systemd credentials | Reuse its application secret contract across development and deployment | Useful only if that application actually consumes SecretSpec |
| Existing CLI with native token-file support | Another retrieval wrapper | Usually little value over the current protected path |
| Bitwarden integration | Additional backend choices | Does not by itself replace the repository's reviewed vault reconciliation workflow |

SecretSpec's [systemd provider](https://secretspec.dev/providers/systemd-credential/)
reads credentials already delivered to a service. A possible composition is
nix-seal runtime file → systemd `LoadCredential` → SecretSpec-aware application.
This preserves nix-seal as the authority, although an application able to read
credential files directly needs no extra resolver.

### Security and operational boundaries

**Delivery does not isolate a process.** In v0.21.1, `run` adds selected secrets
to a child environment while retaining ambient environment variables. Scopes
remove excluded declared names, but do not generally remove provider tokens or
other ambient credentials. A child with access to a provider's credentials or
an unlocked keyring may obtain more than its selected scope. Avoid wrapping an
entire development shell, editor, agent, or build toolchain with production
credentials. Prefer explicit commands with narrowly authorized development
credentials. This follows the released
[`run` implementation](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/secrets.rs#L7500-L7583)
and [scope documentation](https://secretspec.dev/concepts/scopes/).

**SDK/IPC access is an alternative, not a sandbox.** The shipped resolver
protocol supports application requests without using environment variables as
the secret transport. `run` itself has no `--no-env` option. A resolver session
fixes its manifest, profile, and scope; callers still need provider and operating
system restrictions. For a read-only use, explicitly select `serve --read-only`;
the ordinary server also supports mutation. See the released
[resolver protocol](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/docs/src/content/docs/reference/resolver-protocol.mdx)
and [server implementation](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/serve.rs).

**A check is not necessarily a read-only probe.** Ordinary `secretspec check`
can generate and persist missing configured values. `--no-prompt` alone does not
make it read-only. In the reviewed release, `check --json` or `check --explain`
uses the read-only reporting path. Use reporting for inspection and test
mutation separately with disposable providers. Generating a new password does
not update an application's existing password automatically. See the released
[CLI dispatch](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/cli/mod.rs#L1743-L1780)
and [secret resolution implementation](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/secrets.rs#L5835-L5872).

**File delivery still creates plaintext.** `as_path` avoids putting a value in
the child environment, but materializes it as a temporary file. Ordinary run
cleanup relies on temporary-file lifetimes; uncatchable termination can leave
residue. The resolver protocol explicitly accounts for abandoned session files.
Choose a protected volatile temporary directory and test cancellation before
using sensitive file credentials. See the released
[materialization code](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/validation.rs)
and [resolver cleanup contract](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/docs/src/content/docs/reference/resolver-protocol.mdx).

**Provider choice determines storage safety and availability.** Supporting
plaintext files or dotenv does not make them encrypted. Remote vaults introduce
network and bootstrap-credential dependencies. Local keyrings depend on session
availability and unlock behavior; they are a reasonable developer option, not
a replacement for unattended boot delivery. Upstream documents new Keychain
approval prompts after Nix-installed binary upgrades on macOS. See the
[keyring provider](https://secretspec.dev/providers/keyring/).

**Manifest and executable changes affect credential access.** Treat provider
routes, inherited declarations, scopes, and helper executable selection as
security-sensitive code. In the released
[command generator](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/generator.rs#L381),
`type = "command"` executes through `sh -c`, and failure stderr can enter an
error message. Review these declarations before permitting resolution in an
untrusted checkout; do not grant provider credentials to unreviewed fork or PR
code. Project/profile names organize credentials; they do not
establish an operating-system authorization boundary. Pin the CLI and helper
dependencies through the existing Nix dependency workflow rather than adopting
an unpinned installer. Keep resolved values out of evaluation, derivations,
logs, shell tracing, and public defaults. Even the
[devenv integration guide](https://devenv.sh/integrations/secretspec/)
recommends loading at application runtime and limiting delivery to consumers.
There is no need to migrate this repository to devenv just to try the CLI.

**Audit records have limited assurance.** Upstream's
[security policy](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/SECURITY.md)
describes local logging as user-controlled and fail-open. Treat it as diagnostic
history, not tamper-proof access evidence. Primary authorization, storage
protection, availability, and rotation remain responsibilities of the selected
provider. Its release support policy also requires keeping a pinned deployment
current; pinning alone does not maintain security support.

### Release boundaries and replacement cost

The latest release and current documentation are not interchangeable. Main
contains features labelled for 0.22. More importantly,
[`nixos.md` in the released tree](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/nixos.md)
is explicitly a design proposal with stale 0.16/0.17 wording. Its desired
reconciliation, encrypted-credential generations, and restart behavior must not
be counted as a verified, shipped replacement for this repository's activation.
A systemd credential reader is a different capability from managing a complete
NixOS deployment lifecycle.

The released [age backend](https://github.com/cachix/secretspec/blob/5a8927d2b800c604fee72970ffbd137c57820fd5/secretspec/src/provider/age.rs)
decrypts a dotenv map, so sharing the age encryption format does not make it a
drop-in reader for this repository's individual raw-value ciphertext files.
An age or SOPS backend alone also does not establish parity with nix-seal's
signed target-specific policy artifacts. A replacement would need evidence for
ownership, signature enforcement, source/policy binding, boot ordering,
service restart behavior, platform support, recovery, and controlled rollback.
Do not infer rollback protection or author authentication merely from ciphertext
encryption. Retaining an existing older configuration for recovery also needs
an explicit policy about which historical credentials remain acceptable.

## Implication for this repository

Do not add a second authoritative secret inventory or migrate existing
infrastructure credentials for this feature set. Revisit when a concrete
application needs provider portability or a shared development/CI contract.

For that case, trial one application with synthetic or low-privilege development
credentials. Pin a reviewed supported release; define one authoritative store,
an explicit profile and scope, and no production fallback into a developer
keyring. Test missing/locked providers, offline operation, command failure,
rotation, file cleanup, and Linux/macOS behavior. Verify that build outputs,
logs, and unrelated child processes do not receive values. Keep any infrastructure
bridge one-way, with nix-seal as its source, rather than introducing competing
copies that can drift.

## Validation and limits

This assessment inspected public upstream documentation and source, plus local
configuration and policy. Root HEAD was
`21237bdb8974bda44d4a8c591b50e542dd7dc6c3`; local nix-seal HEAD was
`70f87698d7a17a22e76321ccc118733f3e58bfa6`. Both checkouts had existing changes,
and local findings describe their working files rather than those commits alone.

No secret values, private keys, or live providers were read. SecretSpec was not
installed or executed; no migration, activation, service, or recovery test ran.
No independent security audit was established by this source review. It is not
a vulnerability scan, a dependency-advisory clearance, or proof of runtime safety.
Markdown lint, relative-link target checks, whitespace checks, and focused
Gitleaks scans passed for the note and research index. All linked GitHub pages
returned HTTP 200. Direct HTTP checks of the SecretSpec and devenv documentation
received HTTP 403; those pages were successfully read through the web tool.
These checks validate the document, not the software behavior.
