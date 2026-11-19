# Writable VS Code Remote SSH settings through Nix

Reviewed: 2026-11-17. Scope: Remote SSH destination settings, Home Manager
revision `a1293da7dd8e497e08d26173f97e2976b36a31ea`, and VS Code configuration
source at `6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1`. The latter source revision
is an inspected reference, not a verification of every running server version.

## Answer

Keep the destination's `~/.vscode-server/data/Machine/settings.json` writable.
Generate destination-specific settings with Nix and reconcile them during Home
Manager activation. Keep extensions independently managed by Nix. Do not copy
the entire local user profile into an immutable remote settings file.

This recommendation combines upstream configuration behavior with the repository's
need to own executable paths declaratively. No single upstream Home Manager
option currently provides this complete remote-file lifecycle.

## Findings and sources

### Settings belong to different layers

Remote SSH reuses the connecting client's user settings. Remote settings override
ordinary user settings, and workspace settings can override remote settings.
Language-specific and policy settings add further precedence rules. Therefore the
remote file should primarily own destination tooling, runtime paths, and shell
profiles. Themes and ordinary editor preferences can normally remain with the
client. These are recommendations based on the
[Remote SSH settings model](https://code.visualstudio.com/docs/remote/ssh#_remote-hostspecific-settings)
and [settings precedence](https://code.visualstudio.com/docs/configure/settings#_settings-precedence).

VS Code filters remote settings by configuration scope. Its inspected
[`REMOTE_MACHINE_SCOPES`](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/workbench/services/configuration/common/configuration.ts#L28-L34)
excludes application scope. Copying every client setting does not make every
setting effective remotely. An explicit remote settings option, populated by the
features that own language tooling and terminal profiles, gives these settings
clear ownership without maintaining a second independent set of executable paths.

### Home Manager has useful pieces, rather than a remote settings toggle

The pinned VS Code module's `profiles.<name>.mutableUserSettings` handles local
profile settings. It does not target the remote server's Machine file. Its
[mutable settings implementation](https://github.com/nix-community/home-manager/blob/a1293da7dd8e497e08d26173f97e2976b36a31ea/modules/programs/vscode/mutableSettings.nix)
parses JSON5 and recursively merges existing values with Nix values winning.
Removing a key from Nix does not remove its previously merged value on disk.

The public but experimental
[`lib.hm.generators.mkImpureConfigMerger`](https://github.com/nix-community/home-manager/blob/a1293da7dd8e497e08d26173f97e2976b36a31ea/modules/lib/generators.nix#L981-L1242)
supports a custom JSON5 reader, validates input before replacement, stages a
candidate, checks for concurrent changes, and attempts atomic replacement.
It preserves existing file modes and refuses a target resolving into the Nix
store. It does not track retired declarations. Reuse its supported behavior where
possible, but account explicitly for migration and key retirement.

JSON5 accepts the comments and trailing commas commonly used in settings files.
Parsing and serializing to JSON preserves values rather than original comments
and formatting. If preserving comments is a requirement, use structural JSONC
editing instead of a parse-and-reserialize merge.

### Migration is part of the fix

The current [remote module](../../modules/home/vscode/remote.nix) declares the
Machine file through `home.file`, which creates a link into the immutable store.
The destination cannot save edits through that link.

Remove that file declaration, while retaining the extension tree declaration.
Capture the previous generated settings before Home Manager cleans the old
managed link: its
[link-generation lifecycle](https://github.com/nix-community/home-manager/blob/a1293da7dd8e497e08d26173f97e2976b36a31ea/modules/files.nix)
removes obsolete managed links. The old document is useful as the initial record
of keys previously supplied by Nix.

A migration must verify that the link is the expected managed link, validate its
contents, stage an owner-writable regular file beside the destination, and replace
the link itself. Preserve a recovery copy. Never write through or chmod the store
referent. Unexpected links and malformed files should remain untouched.

### Alternatives do not solve the complete problem

- An out-of-store symlink permits edits but does not supply merging, ownership,
  retirement, or safe initialization by itself.
- A custom extension's `configurationDefaults` supplies defaults with lower
  precedence than explicit user settings. The inspected
  [extension point](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/workbench/api/common/configurationExtensionPoint.ts#L215-L235)
  also rejects defaults for several machine/application scopes. It cannot
  reliably override the connecting client's explicit executable paths.
- The inspected
  [settings parser](https://github.com/microsoft/vscode/blob/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/src/vs/platform/configuration/common/configurationModels.ts#L341-L427)
  supplies no general `include` or `extends` expansion for splitting a settings
  file into immutable defaults plus writable overrides.

## Implication for this repository

Implement a destination-side remote settings option with this contract:

1. Language and shell features supply host-specific values from their existing
   Nix definitions. Keep client-only preferences out of this declaration.
2. Activation reconciles a writable Machine file. Declared Nix values win on
   activation; unrelated manual settings survive. Changes to Nix-owned settings
   in the UI remain temporary until the next activation.
3. Record previous declarations. Remove retired owned values that still match
   that record; preserve deliberately changed manual values and unrelated nested
   children. Treat dotted setting names as literal keys, not object traversal.
4. Validate JSONC-compatible input, handle empty declarations, honor dry runs,
   detect concurrent edits, and use recoverable updates of the file and ownership
   record. Invalid input must not be replaced by defaults.
5. Migrate the existing managed symlink explicitly. Verify writable-file behavior,
   repeated activation, Nix path updates, retirement, malformed input, and
   interrupted activation before deployment.

A simple recursive merge can be a smaller interim fix, but its retention of
retired settings must be an explicit policy choice. It should not be described
as exact declarative reconciliation.

## Validation and limits

Primary-source inspection and a nonmutating filesystem probe ran on Linux. The
current Machine settings path resolves through Home Manager into the Nix store;
opening it for editing failed with `EACCES`. The reported VS Code operation failed
with `EROFS`; that exact UI operation was not rerun.

An isolated build for a merge experiment was attempted, then cancelled while Nix
was waiting for the garbage-collector lock. The merge experiment did not run.
No production configuration was changed or activated during this research.
Native Darwin behavior, end-to-end remote editing, extension activation, and
migration/reconciliation behavior remain unverified.
