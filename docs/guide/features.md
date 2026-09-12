# Supported features

The generated guide lists a bounded set of reusable features with their actual
import paths, prerequisites, state ownership and check names. A check name is a
way to obtain evidence, not a claim that the current revision has passed it.
See [support](support.md) and [validation records](validation.md).

<!-- generated-feature-catalog -->

Build `.#feature-catalog` to inspect the machine-readable inventory. The guide
build inserts this same inventory into this page. Its source lives in
[feature-catalog.nix](https://github.com/nix-forge/nix-conf/blob/main/flake/feature-catalog.nix).

The [option reference](options.md) comes from the owning Nix declarations.
The public shell recipes use ordinary Home Manager settings and link their
complete source so preferences stay inspectable.

The Windows guest is an integration feature for a compatible Linux host. Its
[runbook](https://github.com/nix-forge/nix-conf/blob/main/docs/workstation-virtualization.md)
explains installation, state ownership and native validation. It is not part of
the public starter or graphical demonstration.
