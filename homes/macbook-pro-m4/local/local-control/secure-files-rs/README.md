# Local-control secure files

`local-control-secure-files` is the active Rust implementation of the
descriptor-bound local-control filesystem helper. It rejects path traversal
and symlinks during component-by-component resolution, validates ownership and
permissions from already-open descriptors, and writes files through a
same-directory atomic replacement.

The crate deliberately uses `rustix` rather than path-based convenience APIs
for security-sensitive operations. `rustix` exposes the POSIX `openat` family
through Rust ownership types, which preserves the existing design's
descriptor-bound trust boundary without introducing `unsafe` Rust.

## Local development

From this directory:

```console
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --all-targets
cargo audit
cargo deny check
```

`cargo audit` and `cargo deny check` intentionally remain explicit commands:
their advisory data may need a network refresh, which would make an otherwise
reproducible local pre-commit check flaky or impure.

## Compatibility boundary

The package preserves the prior helper's command-line interface, including
generation-file access, mapped inherited file descriptors, proxy credentials,
cluster validation, and deterministic source snapshots. The Nix runtime helper
resolves this package directly; no C source or compiler is part of the active
local-control implementation.
