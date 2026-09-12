# Your first configuration

This exercise builds files for a neutral account called `learner`. You will
inspect Git, Bash, and Starship settings, change one setting, and build again.
The example stays separate from your current account.

## Copy the starter

From the nix-conf checkout:

```sh
guide_dir=$(mktemp -d)
cp -R templates/starter/. "$guide_dir/"
cd "$guide_dir"
guide_system=$(nix eval --impure --raw --expr builtins.currentSystem)
```

The temporary directory is your working copy. Keep it until you finish the
exercise. Copy it to a permanent location later if you want to continue using it.

## Build and inspect

```sh
nix build ".#homeConfigurations.${guide_system}.activationPackage"
cat result/home-files/.config/git/config
cat result/home-files/.config/starship.toml
```

Nix creates a `result` link to the built activation package. It downloads or builds
its dependencies on the first run. No activation command has run, and your live
Git settings are unchanged.

The generated Git configuration includes the default branch and useful aliases.
The Starship configuration defines the prompt shown by the example shell.
Source declarations live in `home.nix` and the small files under `modules/`.

## Read the home declaration

<!-- include: templates/starter/home.nix -->

```nix
{ pkgs, ... }:
{
  imports = [
    ./modules/git.nix
    ./modules/shell.nix
    ./modules/prompt.nix
  ];

  home = {
    # Replace these two values before activating on your own account.
    username = "learner";
    homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/learner" else "/home/learner";

    # Keep this at the version used for your first activation. Input updates do
    # not require changing it; see Home Manager's release notes before doing so.
    stateVersion = "26.05";
  };
  programs.home-manager.enable = true;
}
```

<!-- /include -->

## Change one setting

Open `modules/git.nix`, find `init.defaultBranch`, and change its value to
`trunk`. Build again with the same command, then inspect the Git file again.
Your edit should now appear in the generated configuration. Change it back to
`main` before running the example's checks, which verify its documented defaults.

```sh
nix build ".#checks.${guide_system}.generated-config"
```

This checks generated files. It does not prove interactive activation on your
operating system. The [VM exercise](virtual-machine.md) tests a running Linux
system separately.

## Use it for your own account

Move the example to a permanent directory and put it under your own version
control. Set your actual username and home directory in `home.nix` before
considering activation. Preserve `home.stateVersion` for an existing Home Manager
installation; it controls compatibility behavior, not the package release.

Review the generated configuration and existing files first. The
[Home Manager standalone guide](https://nix-community.github.io/home-manager/nix-flakes/standalone.html)
explains activation and generation management. Home Manager's dry activation
reports planned actions, but initialization can still create profile state; it
is not a promise of zero filesystem writes.

The tutorial ends with a successful build and an observable changed setting.
Next, try [Git defaults](git.md) or [boot the VM](virtual-machine.md).
