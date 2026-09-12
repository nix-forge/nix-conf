# How the configuration fits together

A host owns operating-system policy. A home profile owns a user's applications
and preferences. Reusable features live under `modules/`; settings specific to
one target live beneath that target's `local/` directory.

```text
flake.nix
  -> framework discovers hosts and home profiles
  -> target default.nix selects reusable features
  -> target local/ supplies machine-specific settings
  -> Nix evaluates the merged modules
  -> build produces a system or home generation
  -> activation applies that generation
```

## Follow one setting

Start at a target's `default.nix`. Its `modules` list selects reusable features
provided by nix-config-framework. A selector such as `shells-starship` corresponds
to `modules/home/shells/starship.nix`. Follow that file to the Home Manager option,
then inspect the generated configuration after a build.

The framework automatically imports Nix files beneath a target's `local/`.
Those files must be modules. A reusable directory with a `default.nix` has an
explicit aggregate; a directory without one selects its descendants together.
The [framework contract](https://github.com/nix-forge/nix-config-framework#layout-and-selectors)
explains the details and collision behavior.

## What belongs where

| Change | Owner |
| --- | --- |
| Choose a feature for one machine | Host or home target |
| Reuse a preference across machines | A module under `modules/` |
| Discover and compose targets | nix-config-framework |
| Package an application or font | nixpkgs-personal |
| Implement secret delivery | nix-seal |

The starter uses ordinary imports so you can first see how Home Manager works.
The framework becomes useful when multiple targets need named feature selection.
It does not replace the Nix module system.

The [root contributor guide](https://github.com/nix-forge/nix-conf/blob/main/CONTRIBUTING.md)
and [glossary](https://github.com/nix-forge/nix-conf/blob/main/CONTEXT.md) define the
repository's boundaries. Keep package fixes with their owning package rather
than hiding them inside a workstation preference.
