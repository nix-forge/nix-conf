# Update and recover

Keep the configuration and lockfile in your own Git repository. A lockfile fixes
the inputs used for a build; it does not preserve application databases, documents,
or every piece of mutable state.

## Update the small example

In your permanent copy of the starter, commit a working configuration first.
Update one input, inspect the lockfile diff, and run its checks:

```sh
nix flake update nixpkgs
git diff -- flake.lock
guide_system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build ".#checks.${guide_system}.generated-config"
```

Keep Home Manager and Nixpkgs on compatible release tracks. If you change their
branches to a new release, review that release's Home Manager and NixOS notes.
Updating a lockfile is not a reason to raise `home.stateVersion` or
`system.stateVersion`.

## Diagnose a failed build

Read the first substantive error. Identify whether it came from evaluation,
package building, or activation. Reproduce the smallest named output rather than
rebuilding every host. Record the input revisions and complete command when
asking for help. Share a short redacted error, not your entire environment.

For an update-only failure, restore the previous committed lockfile after
checking that doing so will not discard unrelated edits, then rebuild. A known
working revision is more useful than repeatedly updating every dependency.

## Return to an earlier generation

Home Manager and NixOS keep generation history. Follow
[Home Manager rollback instructions](https://nix-community.github.io/home-manager/usage/rollbacks.html)
and the [NixOS manual](https://nixos.org/manual/nixos/stable/)
for your installation. Preserve needed generations before garbage collection.
The VM gives you a disposable place to practice configuration changes.

A configuration rollback does not undo application database migrations or restore
deleted files. Keep backups and test restoration separately. The personal desktop's
[storage operations guide](https://github.com/nix-forge/nix-conf/blob/main/docs/desktop-storage-operations.md)
is specific to that setup; adapt its reasoning and recovery tests to your own
storage rather than copying its device configuration.
