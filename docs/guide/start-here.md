# Before you start

The first exercise builds a Home Manager configuration and inspects its output.
It does not activate that configuration on your account. You need a working Nix
installation with flakes enabled, Git, an internet connection, and space for
packages in the Nix store.

The starter covers `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. The VM
exercise requires `x86_64-linux` with KVM. Check the [support table](support.md)
for the difference between configured checks and recorded runtime results.

## Check your tools

```sh
nix --version
nix eval --impure --raw --expr builtins.currentSystem
git --version
```

If Nix is missing, follow the [official installation guide](https://nix.dev/install-nix).
If the commands report a disabled experimental feature, follow the
[Nix flake setup guidance](https://wiki.nixos.org/wiki/Flakes#Setup).
The starter follows matching Nixpkgs and Home Manager release branches; its
committed lockfile supplies the exact revisions.

## Get the source

```sh
git clone --recurse-submodules https://github.com/nix-forge/nix-conf.git
cd nix-conf
```

For an existing clone, use `git submodule update --init --recursive` to populate
the three related repositories at their recorded revisions. The public starter
itself has no submodule dependencies.

The complete host targets contain hardware, accounts, and secret policy for the
maintainer's machines. Start with the separate exercise rather than selecting a
personal host for installation.

Continue to [your first configuration](first-configuration.md).
