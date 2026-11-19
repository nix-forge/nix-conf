# Support and validation

The personal workstation and public examples have different support boundaries.
A platform declared in a flake is not evidence that every feature has run there.

The graphical demo runs on x86 Linux. Darwin configurations need an Apple
silicon Mac for a native build. Personal desktop system builds belong on desktop.
Intel macOS is outside the declared public platform set.

## What the checks establish

```sh
nix build .#documentation
just test
just check
```

Documentation checks validate links and generated references. Nix-unit covers
library function contracts; other retained checks perform static analysis.
Module assertions reject invalid setting combinations. There are no automated
public-consumer, VM or generated-configuration assertion suites.
Build the graphical demo using its guide instructions. Activation, hardware,
services and recovery require their actual operator-visible operations.
See [public examples](public-examples.md) for import boundaries.

Use the [Actions history](https://github.com/nix-forge/nix-conf/actions) and record
the source revision with any claim about a result. A working-tree change has not
passed hosted CI until its actual run succeeds.

## Reporting a problem

Use the [bug form](https://github.com/nix-forge/nix-conf/issues/new?template=bug.yml)
or [guide feedback form](https://github.com/nix-forge/nix-conf/issues/new?template=guide-feedback.yml).
The project maintains a focused workstation and learning guide; it cannot promise
support for every hardware combination or every upstream release.
