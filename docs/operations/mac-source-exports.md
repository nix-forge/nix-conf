# Verified Mac source exports

Use a complete verified snapshot for remote Mac builds and tests. Incrementally
copying individual files can pair a newer fixture with an older implementation.
The export tool captures one selected working tree, imports it into the Nix
store, and transfers that exact immutable source to the Mac.

## Default remote commands

The normal remote commands create a fresh verified export automatically:

```sh
just macbook-build
just mac-test -q tests/macos/test_mac_source.py
just mac-check
```

`macbook-build` preserves deploy-rs's dry activation preview. `macbook-deploy`
uses the same export path and retains the configured root SSH and rollback
policy when activation is requested. `macbook-deploy --dry-activate` tests its
pipeline without activation. Transport and source overrides are rejected so the
verified Mac cannot silently differ from the deployment target. Extra Nix build
flags follow `--`, for example `just macbook-build -- --show-trace`.

From Linux, `darwin-build <CONFIGURATION>` and `darwin-switch <CONFIGURATION>`
use these verified remote build/deploy paths. On Darwin, those two commands retain
their local `nh` behavior. `mac-test` realizes the exported flake's pinned test
environment on the Mac, disables the source-directory pytest cache, and forwards
pytest arguments unchanged. With no arguments it selects `tests/macos`; the
repository's marker policy still controls native integration tests.

`mac-exec <COMMAND> ...` runs another command through a fresh export. Each default
operation prints a private receipt path under
`~/.local/state/nix-conf/mac-source-runs/`. Sources and command outcomes stay bound
to that receipt. Deployment-client preparation and deploy-rs's nested local Nix evaluation and
copy operations run through the desktop workload queue. The build against the
verified Mac store runs outside that queue, as do native tests. Queue-placement
records are retained beside the receipt as `.client.nix.jsonl`. A sibling
`.client` root retains the selected deployment client while the operation is
needed, alongside the source root.

## Explicit exports and receipt reuse

The lower-level commands remain available when several commands intentionally
share a source snapshot. Existing `mac-check <RECEIPT>` and `mac-run <RECEIPT>`
usage is preserved and rejects a receipt after selected source changes.

Run from the repository checkout with Git, Nix, Python 3 and SSH available.
Choose a new private receipt filename for each export:

```sh
receipt="$HOME/.local/state/nix-conf/mac-source-exports/<RUN>/export.json"
just mac-export "$receipt"
just mac-check "$receipt"
```

`mac-export` defaults to the configured `macbook` SSH alias. Pass a different Mac
alias as its second argument. `mac-check` runs the broader temporary-fix check,
whose assertions evaluate all three supported platforms on the native Mac.
It does not activate a configuration.

Run other commands through the same verifier:

```sh
just mac-run "$receipt" nix build --no-link --no-write-lock-file \
  --max-jobs 2 --cores 4 \
  '.#darwinConfigurations.macbook-pro-m4.config.system.build.toplevel'
just mac-run "$receipt" python3 -m pytest -p no:cacheprovider \
  tests/macos/test_mac_source.py
```

Common Nix source overrides (`--expr`, `--file`, input overrides and unrelated
installables) are rejected. The Nix guard accepts `build`, `eval`, `develop`,
and `flake check`, `metadata` or `archive`, with the common build/output flags
used above. Unknown flags fail closed rather than guessing which arguments are
source selectors. Nix installables must select the snapshot root. Absolute root selectors are
normalized to `.#target` before execution: inside a store directory, Nix can
otherwise treat an absolute flake URL as an opaque store path and ignore its
target. Commands must use the snapshot working directory or
`{source}`; the runner does not certify unrelated source chosen inside custom
shell scripts or other programs.

Arguments retain their boundaries through SSH; `{source}` expands to the exact
verified Nix-store source. Commands run in that source directory. Tests must put
outputs in their temporary directories: the source is immutable. Python bytecode
writes are disabled automatically; disable pytest's source-directory cache as
shown above. Use the repository's test Python environment when pytest or its
configured plugins are not installed in the ordinary Mac interpreter.

Exporting hashes and transfers source; compilation and native tests run on the
Mac. Other heavy desktop checks still use `workstation-task` as required by the
repository's build-placement policy.

## Source selection and identity

The snapshot includes current working bytes of tracked files, including staged,
unstaged and intent-to-add files. Tracked deletions remain deleted. Initialized
submodules are traversed recursively, including their dirty working bytes;
missing submodules and unresolved index conflicts block the export. Git metadata
is excluded. No commit, index update or working-tree reset is performed.

Untracked files are excluded by default, matching the repository's ordinary Git
source selection. For a new source file, add it deliberately to Git or select it
explicitly without changing the index:

```sh
just mac-export "$receipt" macbook --include scripts/new_helper.py
```

Ignored files cannot be explicitly included. Relative symlinks that stay inside
the snapshot are preserved. Absolute or escaping symlinks, special files and
redirected parent directories are rejected.

The manifest records every selected path's SHA-256, executable flag or symlink
target, plus each repository's HEAD and index identity. Its digest is stored in
the local receipt. The tool inventories the working tree before and after
copying, verifies the staged copy, and publishes no successful receipt if those
observations differ. This detects observed concurrent writes; it is not a lock
on other writers. Use a dedicated task checkout when concurrent edits prevent a
stable export.

## Checks before and after commands

Before launching SSH, `mac-run` verifies that the selected local source still
matches the receipt. An older receipt after a local edit is rejected with an
instruction to export again. On the Mac, the trusted verifier is sent from the
caller over SSH rather than loaded from a potentially stale export. It checks
the expected manifest digest and scans the complete source for missing, extra,
modified or redirected files before starting the requested command.

Both local freshness and remote integrity are checked again after execution.
A change detected then invalidates the result. The private `.last-run.json`
receipt records the exact source identity, arguments and outcome; validation
failures replace any previous successful status. A build that exits successfully
cannot certify source changes made after its snapshot was captured.

The exported source has garbage-collection roots beside the local receipt and
under `~/.local/state/nix-conf/mac-sources/` on the Mac. Keep these while a snapshot
is needed. Review and remove only the specific roots when finished. Existing
mutable temporary exports are historical evidence; do not use them for new
build or test commands.
