# Atuin Nushell keybinding warning

## Conclusion

This needs an upstream fix in the affected Atuin version, but no new upstream
PR should be opened. Atuin already merged the exact minimal fix in
[#3975](https://github.com/atuinsh/atuin/pull/3975), and released it in
[v18.20.1](https://github.com/atuinsh/atuin/releases/tag/v18.20.1). The local
package is v18.19.0, so it still generates the broken integration.

The right local follow-up is to use `atuin >= 18.20.1` and remove the Nix
post-processing workaround once that version is available. Keeping the
workaround after the update would duplicate upstream behavior and make a future
change to Atuin's generated script harder to diagnose.

## What failed

Atuin v18.19.0 generated both the Ctrl-R and Up Arrow Nushell bindings with the
name `atuin`. Nushell 0.115.1 intentionally preserves both bindings but warns
when names are shared. The report at
[#3971](https://github.com/atuinsh/atuin/issues/3971) contains the same startup
warning as the affected system.

Nushell previously had a worse failure mode. Its 0.115.0 merge behavior silently
discarded one same-named binding, which removed Atuin's Ctrl-R shortcut. Nushell
fixed that behavior in [#18870](https://github.com/nushell/nushell/pull/18870)
and added the warning so integrations can correct their duplicate names. This
is why suppressing the warning in Nushell would be the wrong fix.

## Upstream implementation

Atuin [#3975](https://github.com/atuinsh/atuin/pull/3975) changes only
`crates/atuin/src/command/client/init/nu.rs`:

- Ctrl-R keeps the name `atuin`.
- Up Arrow changes from `atuin` to `atuin_up_arrow`.
- A regression test extracts both generated binding names and fails if they are
  not unique.

That is the appropriate seam and test. It keeps the existing shortcut behavior,
matches Nushell's unique-name requirement, and tests the generated text rather
than a downstream rewrite. The PR merged on 2026-08-25. It missed v18.20.0,
which had already been published, so v18.20.1 is the first fixed release. The
[v18.20.1 release notes](https://github.com/atuinsh/atuin/releases/tag/v18.20.1)
explicitly list "Use unique keybinding names".

## Contribution guidance

Atuin's [contribution guide](https://github.com/atuinsh/atuin/blob/main/CONTRIBUTING.md)
requires contributors to understand and test AI-assisted changes, asks for a
concise PR description, uses `cargo +nightly fmt` as the formatting authority,
and places tests next to the code under test. The merged PR follows that shape:
one behavior change and a targeted regression test.

No additional Nushell PR is warranted either. [Nushell #18870](https://github.com/nushell/nushell/pull/18870)
is merged and explains that duplicate names remain supported with a one-time
warning. Atuin must provide distinct names to avoid that valid diagnostic.

## Recommended verification after packaging update

1. Evaluate the Darwin configuration and confirm Atuin resolves to at least
   v18.20.1.
2. Generate the Nushell integration with `atuin init nu` and assert that the
   two bindings are named `atuin` and `atuin_up_arrow`.
3. Start a clean login Nushell and confirm there is no
   `nu::shell::shared_keybindings_name` warning.
4. Confirm both Ctrl-R and Up Arrow still invoke Atuin.

## Nixpkgs availability

As of 2026-09-01, nixpkgs `master` still packages Atuin 18.19.0. Updating it
to either 18.20.1 or 18.21.0 is not currently a valid standalone package PR:
both releases declare Rust 1.98.0 as their minimum compiler version, while
nixpkgs `master` provides Rust 1.97.1. A sandboxed aarch64-darwin package build
fails at that declared version check before compilation.

Therefore a Nixpkgs update PR should wait for Rust 1.98.0 to land. Submitting
one now would knowingly fail CI. Until then, the local generated-config
workaround is an appropriate compatibility bridge; it should be removed after
the package update is available.
