# Try a small Apple silicon system

The `darwin` template provides a neutral nix-darwin system with exact stable
26.05 pins. It manages Git, jq, a Zsh alias, and a harmless LaunchDaemon without
requiring a personal account or any secret.

From the root checkout with initialized submodules:

```sh
example_dir=$(mktemp -d)
repo=$PWD
cd "$example_dir"
nix flake init --template "git+file://$repo?submodules=1#darwin"
nix build --no-write-lock-file .#checks.aarch64-darwin.system
nix build --no-write-lock-file .#checks.aarch64-darwin.generated-config
```

Run these builds on Apple silicon with Nix installed. They do not activate the
configuration. Read the extracted `README.md` and `configuration.nix` before
adapting or activating anything. The example deliberately leaves ownership of
the existing Nix daemon with its installer.

The generated-config check parses the real Zsh and launchd output and executes
the pinned daemon command. It does not register a launchd job. Loading the job,
opening a new shell, activation, and rollback require a separate attended macOS
check. Linux can evaluate the system derivation but cannot establish those
native results. Intel macOS is outside the declared target set.

See [public consumer checks](public-examples.md) for candidate template
extraction and the distinction between stable examples and current workstation
module consumers.
