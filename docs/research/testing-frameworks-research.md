# Nix library testing framework

Reviewed 2026-11-15. This decision supersedes the earlier multi-language behavioral
testing policy. Tests are restricted to functions in the owning library directories;
nix-seal additionally retains Rust tests. Other automated checks are static analysis.
Upstream package tests and production safeguards remain unchanged.

Use `nix-unit` from each repository's pinned Nixpkgs. Both currently pinned
Nixpkgs revisions provide version 2.35.1. It supports Nix expressions, named
expected values, nested suites and individual evaluation-error reporting.
Specific rejection contracts use `expectedError.type` and message matching.
[Runner documentation](https://nix-community.github.io/nix-unit/),
[versioned error cases](https://github.com/nix-community/nix-unit/blob/v2.35.1/doc/src/examples/errors.md).

`lib.runTests` is already available in Nixpkgs, but returns a list of failed cases
which the caller must force and turn into failure. Nix-unit supplies that runner
behavior without assertion wrappers and isolates evaluation errors per case.
[Implementation](https://github.com/NixOS/nixpkgs/blob/master/lib/debug.nix).

Namaka maintains snapshots and a review/acceptance workflow. That extra state is
unnecessary for the small explicit library contracts here.
[Upstream project](https://github.com/nix-community/namaka).

Expose `libTests` for local selection and a `lib-tests` flake check for CI. Checks
import only the library suite and pinned Nixpkgs library, with an isolated writable
evaluation store; they must not evaluate complete hosts or fetch inputs during the build.
Use the runner's packaged evaluator libraries together rather than relinking it to
the system Nix implementation.
[Flake integration](https://nix-community.github.io/nix-unit/examples/flakes.html).

This choice does not establish performance improvements or runtime correctness.
The removed behavioral and VM suites supplied evidence that static checks and
module assertions cannot replace. Check results and platform limitations belong
in implementation validation records, not framework capability claims.
