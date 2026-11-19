# Before you start

You need a working Nix installation with flakes enabled, Git, an internet
connection, and space for packages in the Nix store. The graphical VM requires
`x86_64-linux` with KVM. Check the [support table](support.md) for build and
runtime boundaries.

## Check your tools

```sh
nix --version
nix eval --impure --raw --expr builtins.currentSystem
git --version
```

If Nix is missing, follow the [official installation guide](https://nix.dev/install-nix).
If the commands report a disabled experimental feature, follow the
[Nix flake setup guidance](https://wiki.nixos.org/wiki/Flakes#Setup).

## Get the source

```sh
git clone --recurse-submodules https://github.com/nix-forge/nix-conf.git
cd nix-conf
```

For an existing clone, use `git submodule update --init --recursive` to populate
the related repositories at their recorded revisions.

The complete host targets contain hardware, accounts, and secret policy for the
maintainer's machines. Start with a [reusable module](git.md) in your own Home
Manager configuration or try the [graphical VM](graphical-demo.md).
