{
  description = "Ian's Nix Configuration";

  # outputs =
  #   { flake-parts, ... }@inputs:
  #   flake-parts.lib.mkFlake { inherit inputs; } (
  #     { withSystem, ... }:
  #     {
  #       # systems for which you want to build the `perSystem` attributes
  #       systems = import inputs.systems;

  #       imports = [
  #         ./flake/checks

  #         ./flake/fmt.nix
  #       ];

  #       flake = { };
  #     }
  #   );

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

      # Nix formatter for this flake
      formatter = eachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt-rfc-style
      );

      # System Modules
      nixosModules = lib.bird.importDir' ./_nixosModules null;

      # Home Modules
      homeModules = lib.bird.importDir' ./_homeModules null;

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

  # The inputs of the flake
  inputs = {
    # The Nixpkg flakes
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-small.url = "github:NixOS/nixpkgs/nixos-unstable-small"; # moves faster, has less packages

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Systems
    systems.url = "github:nix-systems/default-linux";

    # Flake Parts
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-small";
    };

    # Flake Utils
    flake-utils = {
      url = "github:numtide/flake-utils";
    };

    # Flake Compat
    flake-compat = {
      url = "github:edolstra/flake-compat";
    };

    # Bird Nix Lib
    bird-nix-lib = {
      url = "github:spikespaz/bird-nix-lib";
      inputs.nixpkgs.follows = "nixpkgs-small";
    };

    # NUR
    nur.url = "github:nix-community/NUR";

    # VS Code
    vscode-insider = {
      url = "github:iosmanthus/code-insiders-flake";
      inputs.nixpkgs.follows = "nixpkgs-small";
    };
    vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
        flake-utils.follows = "flake-utils";
      };
    };

    # Hyprland Flake
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      ref = "refs/tags/v0.41.0";
      submodules = true;
    };

    # Firefox BetterFox
    firefox-betterfox = {
      url = "github:yokoffing/Betterfox";
      flake = false;
    };

    # Firefox Lepton UI
    firefox-lepton-ui = {
      url = "github:black7375/Firefox-UI-Fix";
      flake = false;
    };

    # Spicetify
    spicetify-nix = {
      url = "github:the-argus/spicetify-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    # Nix gaming
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs = {
        nixpkgs.follows = "nixpkgs-small";
        flake-parts.follows = "flake-parts";
      };
    };

    # Nix Language Server
    nixd = {
      url = "github:nix-community/nixd";
      inputs = {
        nixpkgs.follows = "nixpkgs-small";
        flake-parts.follows = "flake-parts";
      };
    };

    # BirdOS
    birdos = {
      url = "github:spikespaz/dotfiles";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs";
        nixpkgs-unstable.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        nur.follows = "nur";
        vscode-extensions.follows = "vscode-extensions";
        hyprland-git.follows = "hyprland";
        nixd.follows = "nixd";
        bird-nix-lib.follows = "bird-nix-lib";
        ragenix.follows = "";
        hyprnix.follows = "";
        slight.follows = "";
        nil.follows = "";
        waybar.follows = "";
        hyprland-xdph-git.follows = "";
        hyprland-protocols-git.follows = "";
        hyprlang-git.follows = "";
        nix-your-shell.follows = "";
        homeage.follows = "";
      };
    };

    # Nix Direnv
    nix-direnv = {
      url = "github:nix-community/nix-direnv";
      inputs = {
        nixpkgs.follows = "nixpkgs-small";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    # Stylix
    stylix = {
      url = "github:danth/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs-small";
        home-manager.follows = "home-manager";
        flake-compat.follows = "flake-compat";
      };
    };

    # A tree-wide formatter
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs-small";
    };
  };

  nixConfig = {
    # instances of cachix for package derivations
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };
}
