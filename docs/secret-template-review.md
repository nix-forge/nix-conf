# Secret template review

Reviewed on the desktop on 2026-09-07. Public template preparation and tests are
complete. Live ciphertext authoring, artifact provisioning, and deployment are
pending authorized access to the required credentials and target machines.
Private credential-location and connectivity notes are kept outside the public
repository.

## Inventory

There are 15 canonical `.age` files. Four target configurations declare 14 unique
sources because the desktop system deliberately shares the home Nix token
source. The old desktop-specific Nix token ciphertext has no current consumer;
it was retained without decryption or deletion.

| Material | Review and change |
| --- | --- |
| Four Git name/email snippets | Inspected the activated home values in memory. Public templates prepared for four private identity fields. |
| Git allowed signers | Inspected in memory. Reuse the three email fields; keep the existing MacBook public key and Git-only namespace restriction. |
| Cornell SSH include | Inspected in memory. Protect the NetID alone and render the `User` directive at activation. |
| Home Nix access token config | Inspected in memory. Protect the GitHub token alone; keep `access-tokens` and the hostname in the template. The desktop system consumes the same field ciphertext with root ownership. |
| macOS system Nix access token config | Declaration reviewed. The migration parser supports it; its canonical plaintext awaits the administrator key. Its separate scope remains intact. |
| macOS FlakeHub netrc | Declaration and consumer reviewed. Parser prepared for explicit FlakeHub machine entries with separate login/password fields. Actual contents await the key. |
| macOS service environment | Declaration and consumer reviewed. Parser prepared to split each environment value while keeping names and file structure public. Actual contents await the key. |
| Wi-Fi SSID and passphrase | Already separate ciphertext fields feeding an IWD template. Retained. |
| Hugging Face token | Already an opaque token read through `HF_TOKEN_PATH`. Retained. |
| Smithsonian API key | Already an opaque key delivered as a systemd service credential. Retained. |
| Old desktop Nix token source | Unreferenced encrypted original. Retained pending explicit retirement after successful deployments. |

Seven home configuration templates are prepared in `secrets/templates.json`.
Their field ciphertexts do not exist yet, so all current configurations still
use the original runtime secret paths. The MacBook-only inventory entries will
be generated after their plaintext passes the migration's strict parsers.

Jujutsu also has a prepared runtime identity template. It activates when the new
Git name/email fields are declared, and replaces the persistent generated
identity file with a runtime symlink. The old identity behavior remains in place
until then.

## Validation

- Six automated tests pass, covering application syntax, shared identity
  values, signer restrictions, rejection of ambiguous/injected input, and real
  nix-seal batch encryption and private template rendering with a disposable
  identity. Run `python3 tests/secrets/test_template_migration.py`.
- A separate disposable fixture exercised the full migration helper against
  nine config inputs. Batch authoring, encrypted round trips, public inventory
  output, and retention of originals succeeded without printing test values.
- Nix evaluation with a separate field fixture selected all seven home
  templates on Linux and macOS, preserved `user`/`staff` groups, and preserved
  root ownership for the system token template. This also passed with
  import-from-derivation disabled. Public templates use architecture-independent
  store text or checked-in files.
- The migrated Jujutsu branch evaluated on both platforms with a runtime
  symlink and without passing identity values in command arguments.
- All current NixOS desktop and nix-darwin MacBook configuration assertions pass.
- Ruff lint, Ruff formatting, and ty checks pass for the new Python files.
- Redacted Gitleaks scans found no credentials in `homes`, `hosts`, `modules`,
  `secrets`, `scripts`, or `tests/secrets`. This is a detector result, not proof
  that every possible credential format is absent.

No private key contents or decrypted values were printed. No live ciphertext
was changed, no sudo policy was changed, and no system was activated. Full
desktop closure builds remain restricted to the desktop host.
