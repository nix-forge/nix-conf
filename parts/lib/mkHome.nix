{
  # The flake inputs
  inputs,
  # Defines the lib (allows for custom lib to be passed in)
  lib,
  # The type of system to build for
  system,
  # The input of nixpkgs to use for the host.
  # Arguments to be given to nixpkgs instantiation.
  # <https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/impure.nix>
  nixpkgsArgs ? { },
  # Overlays to apply to nixpkgs
  overlays ? [ ],
  # Additional `specialArgs` (overwrites `args` attributes).
  specialArgs ? { },
  # define the home-manager flake
  # The modules to include in the home-manager for the system
  modules ? [ ],
  # Define the username to use for the home-manager
  username ? "user",
  ...
}:
let
  inherit (inputs) nixpkgs home-manager;
  # Define the pkgs for the system
  pkgs =
    import nixpkgs {
      inherit overlays;
      localSystem = system;
    }
    // nixpkgsArgs;
  # Define the SpecialArgs
  extraSpecialArgs = specialArgs // {
    inherit nixpkgs lib;
  };
in
home-manager.lib.homeManagerConfiguration {
  inherit system pkgs extraSpecialArgs;
  modules = [ { home.username = username; } ] ++ modules;
}
