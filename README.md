# Nix Configuration

This repository contains a Nix flake used to build NixOS, Nix Home Manager, and
macOS Darwin systems.

These configurations fall into two scopes one system scope and the other is the
home scope. The system scope requires sudo access while the home scope is based
on the user and does not require sudo. The idea is to store as much of the
configuration in the home scope without having drawbacks. This results in the
double effect of having increased compatibility and potentially making your
system more secure.

This flake uses heavy abstraction of the base nix language to define the setup
of configurations. However, each module that the configurations call try to be
as close to standard nix language as possible.

The reason for the heavy abstraction is that it allows us to define our system
configuration definitions like a simple list of modules or packages. When you
define your system, you just want to write a list of items, and the
configuration should easily interpret what you want.

The reason for the close to standard Nix for the modules is that this allows for
easy interpretation from other to understand what a specific module does. It
also allows for someone to easily copy this modules into there configuration.
There are many other public repos that have extensive Nix configurations but the
write lots of custom libs that they use through out there configuration. This is
good for that user but unless these functions are documented and easy to
understand then these configurations become hard for the public to understand
and contribute to them.

That being said there are custom lib functions that are used sparingly. However,
these custom lib functions are explicitly defined writing the full path to
function `lib.cust` for each custom function instead of defining each custom
function in the same path as the Nix standard lib functions, `lib`.

## Directory Layout

- `hosts/` – System specific configuration definitions for NixOS or Nix-Darwin.
- `homes/` – Home‑Manager setups that can stand alone or be added to a host.
- `configs/` – Reusable modules for NixOs, Nix-Darwin, and Home-Manager.
- `nixosModules/` – Standalone Nix style options/config modules for NixOS.
- `pkgs/` – Custom packages that update with GitHub actions.
- `flake/` – Flake modules and setup definitions.

## Requirements

- `Nix` with flakes enabled (Use Determinate Nix with the
  [Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer)).
- Optional: A personal secrets repo using
  [agenix](https://github.com/ryantm/agenix) for importing secrets.

## Building and Installing a Host

_Keep in mind that you do not need to build a host before you switch to it.
Switching to a host will automatically build the host and switch to it._

- Linux (NixOS):

  ```bash
  nix build .#nixosConfigurations.<host>.config.system.build.toplevel
  ```

- macOS (nix-darwin):

  ```bash
  nix build .#darwinConfigurations.<host>.system
  ```

Replace `<host>` with one of the directories under `hosts/`.

The resulting build can be switched to with:

- Linux: `sudo nixos-rebuild switch --flake .#<host>`
- macOS: `sudo darwin-rebuild switch --flake .#<host>`

If you need ssh keys for the system on darwin systems you can use the command
`sudo ssh-keygen -A`.

## Home Manager Systems

Home Manager configurations are located under `homes/`. Each host imports one of
these collections. The ability to build a standalone home-manger system is
possible however the setup as yet to be defined for it.

Currently the Home-Manager systems are used by the systems. This allows the
system to defined what users they want and home-manager configuration they want
for that user on the system. Additionally, the system can pass information to
the Home-Manger system and about the host to allow for better consistency.

## Secrets

Some parts of the configurations expect encrypted secrets from my private
[nix-secrets](https://github.com/IanHollow/nix-secrets) repository managed with
agenix. This repo is a collections already encrypted with each of my systems
public ssh key which are decrypted at runtime using the host SSH key.

In future there might be a better to allow users to reuse this flake but
currently you have to manually change this.

## Custom packages

A few small packages are provided under `pkgs/`. They can be built via
`nix build .#<package>`.

---

This flake is a work in progress and may change frequently. Feel free to explore
the modules, contribute, and reuse anything that looks helpful!
