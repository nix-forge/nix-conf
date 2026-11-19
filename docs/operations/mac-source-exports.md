# Verified Mac source exports

Exporting hashes and transfers source; compilation and native tests run on the
Mac.

Use a complete verified snapshot for remote Mac builds and tests. Incrementally
copying individual files can pair a newer fixture with an older implementation.
The export tool captures one selected working tree, imports it into the Nix
store, and transfers that exact immutable source to the Mac.

The Mac needs a trusted native verifier before the first remote export. The
Darwin dev profile supplies it. To bootstrap without a system rebuild, run
these commands **on the Mac** from a reviewed checkout with initialized
submodules:

```sh
mkdir -p "$HOME/.local/state/nix-conf"
nix build --no-update-lock-file \
  --out-link "$HOME/.local/state/nix-conf/mac-verifier" .#mac-source
```

The exporter prefers the verifier in the Mac's noninteractive SSH command path
and looks at this independent build link when it is absent. It verifies the
snapshot before any command runs from that source.

## Default remote commands

The normal remote commands create a fresh verified export automatically:

```sh
just macbook-build
just mac-test
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
their local `nh` behavior. `mac-test` runs the exported flake's pinned `nix-unit` library runner on the Mac
and forwards its arguments. Runtime acceptance remains an explicit operator task;
no root Python integration suite is installed.

`mac-exec <COMMAND> ...` runs another command through a fresh export. Each default
operation prints a private receipt path under
`~/.local/state/nix-conf/mac-source-runs/`. Sources and command outcomes stay bound
to that receipt. Only deployment-client preparation, evaluation and transfer
run on the caller. Builds and native tests use the verified Mac store.
The `.client.nix.jsonl` file beside the receipt records the deployment client's
Nix arguments. A sibling `.client` root retains the deployment client
alongside the source root.

## Explicit exports and receipt reuse

The lower-level commands remain available when several commands intentionally
share a source snapshot. Existing `mac-check <RECEIPT>` and `mac-run <RECEIPT>`
usage is preserved and rejects a receipt after selected source changes.

Run from the repository checkout with Git, Nix, SSH and the Nix-packaged `mac-source` command available.
Choose a new private receipt filename for each export:

```sh
receipt="$HOME/.local/state/nix-conf/mac-source-exports/<RUN>/export.json"
just mac-export "$receipt"
just mac-check "$receipt"
```

`mac-export` defaults to the configured `macbook` SSH alias. Pass a different Mac
alias as its second argument. `mac-check` runs `nix flake check --no-write-lock-file`
on the Mac, which builds the native flake checks.

Run other commands through the same verifier:

```sh
just mac-run "$receipt" nix build --no-link --no-write-lock-file \
  --max-jobs 2 --cores 4 \
  '.#darwinConfigurations.macbook-pro-m4.config.system.build.toplevel'
just mac-run "$receipt" nix develop --command nix-unit --flake '{source}#libTests'
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
verified Nix-store source. Commands run in that source directory. Commands must put outputs outside the immutable source. The remote machine must
have the trusted `mac-source` verifier from the dev profile or the native
bootstrap build.

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
just mac-export "$receipt" macbook --include scripts/new-helper/src/main.rs
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
instruction to export again. The Mac's trusted native verifier checks the
expected manifest digest and scans the complete source for missing, extra,
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
