{
  description = "Ian's NixOS Configuration";

  # The inputs of the flake
  inputs = {
    # The Nixpkg flakes
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs.follows = "nixpkgs-unstable";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Systems
    systems.url = "github:nix-systems/default";

    # Bird Nix Lib
    bird-nix-lib.url = "github:spikespaz/bird-nix-lib";

    # Nixfmt
    nixfmt.url = "github:nixos/nixfmt";

    # Hyprland Flake
    hyprland-git.url = "github:hyprwm/Hyprland";
  };

  nixConfig = {
    # instances of cachix for package derivations
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      systems,
      ...
    }:
    let
      inherit (self) lib tree; # Allow referencing defined lib and tree
      eachSystem = lib.genAttrs (import systems); # Define to allow packages for multiple systems
    in
    {
      # Overlay default lib with new lib
      # New lib docs -> https://github.com/spikespaz/bird-nix-lib
      # Default lib docs -> https://teu5us.github.io/nix-lib.html
      lib = nixpkgs.lib // {
        bird = lib.extend inputs.bird-nix-lib.lib.overlay; # Bird Nix Lib
        cust = import ./lib { lib = nixpkgs.lib; }; # My Custom Lib
      };

      # Define tree to refer to any file path in the config starting from the root
      tree =
        let
          configRoot = ./.;
          excludes = [ "flake.nix" ]; # flake.nix is excluded to prevent infinite recursion
        in
        lib.bird.importDirRecursive configRoot excludes;

      # Define the formatter for the config
      formatter = eachSystem (system: inputs.nixfmt.packages.${system}.default);

      # System Modules
      nixosModules = lib.bird.importDir' ./_nixosModules null;

      # Home Modules
      homeModules = { };

      # System Configuration
      # Look at each host in the hosts directory and allow them to inherit the vars if needed
      nixosConfigurations =
        let
          hostsDir = ./hosts;
          excludes = [ "shared" ]; # "shared" directory will store configs shared between hosts
          vars = {
            inherit
              self
              lib
              tree
              inputs
              nixpkgs
              ;
          };
        in
        lib.mapAttrs (host: config: lib.bird.applyAutoArgs config vars) (
          lib.bird.importDir' hostsDir excludes
        );

      # Define standalone Home Manager configurations
      homeConfigurations = { };
    };
}
