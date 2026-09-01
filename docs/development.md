# Development

The reproducible development environment is provided by the Nix flake:

```sh
direnv allow
nix develop
prek run --all-files
```

The dev partition contains formatters, linters, security scanners, Nix language
tooling, and the repository hooks. Expensive checks such as the full flake
evaluation and Rust audit/test suites run in pre-push hooks or CI.

To install or refresh hooks for a clone without entering its development shell,
run `just hooks` from any directory. The command resolves the repository from
its justfile and installs hooks only in that clone; it does not retain another
developer's checkout path.

On Windows, direnv is supported through WSL or Git Bash. If Nix is absent,
`.envrc` loads only a small project-root/path environment so shell startup does
not fail; it does not provide the reproducible tools above. Native PowerShell
direnv is outside the supported scope.
