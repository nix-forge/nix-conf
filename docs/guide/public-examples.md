# Public examples

The [graphical demo](graphical-demo.md) provides a disposable local Sway session.
It and the reusable modules use the workstation's current unstable inputs.
Build the demo on its intended platform and follow its launch instructions.
These examples do not promise compatibility with arbitrary release combinations.

Typed module imports use the root flake and its inputs:

```nix
inputs.nix-conf.modules.homeManager.dev-git
inputs.nix-conf.modules.homeManager.shells-fzf
inputs.nix-conf.modules.homeManager.shells-integration
inputs.nix-conf.modules.homeManager.shells-starship
```

Use `git+https://github.com/nix-forge/nix-conf?submodules=1` for typed imports.
Direct source-file imports need neither submodules nor the complete root flake.
See the [Git recipe](git.md) for the `flake = false` source-input alternative.
Module types and assertions validate configuration combinations. Static checks
and library tests do not establish activation or graphical runtime behavior.
