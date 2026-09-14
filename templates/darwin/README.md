# A neutral Apple silicon nix-darwin system

This independent flake manages Git, jq, Zsh configuration, and one harmless
LaunchDaemon on `aarch64-darwin`. Nixpkgs and nix-darwin use matching 26.05
release branches with exact revisions in `flake.lock`. It contains no personal
account, Homebrew, secrets, GUI applications, or hardware identifiers.

## Build before activation

Copy this directory outside the checkout, or initialize the repository's
`darwin` template. On Apple silicon with Nix installed and flakes enabled:

```sh
nix build --no-write-lock-file .#checks.aarch64-darwin.system
nix build --no-write-lock-file .#checks.aarch64-darwin.generated-config
```

The first command builds the complete example system without activating it.
The second parses the generated Zsh configuration and LaunchDaemon plist and
executes the daemon's pinned command. It does not load the job into launchd.
Both checks are Darwin outputs; there is no successful Linux placeholder.

Linux can evaluate the system and its module assertions:

```sh
nix eval --raw --no-write-lock-file .#darwinConfigurations.example.system.drvPath
```

Evaluation is useful for catching option errors. It does not establish native
build success, launchd loading, shell startup, or activation on macOS.

## Adapt and activate

Read `configuration.nix` and the
[nix-darwin installation instructions](https://github.com/nix-darwin/nix-darwin#installing).
The example leaves `nix.enable = false` so the current installer retains ownership
of the Nix daemon. Review that choice against your installer's instructions before
changing it. Keep `system.stateVersion` at the version of your first activation.

After reviewing the built files, activate with the executable from that exact
build rather than fetching another nix-darwin revision:

```sh
sudo ./result/sw/bin/darwin-rebuild switch --flake .#example
```

Build `checks.aarch64-darwin.system` last if `result` points to another check.
After activation, inspect the job and open a new Zsh terminal:

```sh
sudo launchctl print system/org.nix-community.public-example-health
alias gs
```

The job runs `true` once at load and exits successfully. A stopped job with exit
code zero is expected. This example demonstrates managed launchd configuration;
it is not a workstation health monitor.

Use `darwin-rebuild --list-generations` and the rollback instructions in the
[nix-darwin manual](https://nix-darwin.github.io/nix-darwin/manual/) before making
further system changes. A build does not test rollback or validate your existing
machine's installer compatibility. Intel macOS, Linux builds, and automatic
activation are outside this example's support boundary.
