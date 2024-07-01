{
  description = "Ian's Nix Configuration";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, ... }:
      {
        # Parts of the flake that are used to construct the final flake.
        imports = [ ./parts ];

        # Systems for which the attributes of `perSystem` will be built
        # add more if they can be supported...
        #  - x86_64-linux: Desktops, laptops, servers
        #  - aarch64-linux: ARM-based devices, PoC server and builders
        #  - ...
        systems = import inputs.systems;

        flake =
          let
            inherit (inputs.self) lib tree;
            inherit (lib.cust.builders) mkHost;
            inherit (lib.cust.files) importDirRec;
          in
          {
            # Entry-point for NixOS configurations.
            nixosConfigurations =
              let
                hostDir = ./hosts;
                excludes = [ "shared" ];
                vars = hostname: {
                  inherit withSystem;
                  inherit inputs;
                  inherit (inputs) self;
                  inherit (inputs.self) lib tree;
                  inherit hostname;
                };
              in
              lib.mapAttrs (
                hostname: config_fn:
                let
                  vars' = vars hostname;
                  config = config_fn vars';
                  configWithVars = config // vars';
                in
                mkHost configWithVars
              ) (importDirRec hostDir excludes);

            # NixOS Modules
            nixOSModules = importDirRec ./_nixOSModules [ ];

            # Home Manager Modules
            homeManagerModules = importDirRec ./_homeModules [ ];
          };
      }
    );

  inputs = {
    # Systems
    systems.url = "github:nix-systems/default-linux";

    # Feature-rich and convenient fork of the Nix package manager
    # NOTE: Not changing inputs due to it invalidating the cache
    nix-super.url = "github:privatevoid-net/nix-super";

    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    bird-nix-lib = {
      url = "github:spikespaz/bird-nix-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Powered by
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NUR
    nur.url = "github:nix-community/NUR";

    # Ever wanted nix error messages to be even more cryptic?
    # Try flake-utils today! (Devs I beg you please stop)
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    # This exists, I guess
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # A tree-wide formatter
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Spicetify for theming spotify
    spicetify-nix = {
      url = "github:the-argus/spicetify-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    # Hyprland Flake
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      ref = "refs/tags/v0.41.1";
      submodules = true;
      inputs = {
        nixpkgs.follows = "nixpkgs"; # should update nixpkgs when changing hyprland version
      };
    };

    # Nix Language Server
    nixd = {
      url = "github:nix-community/nixd";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # Nix Direnv
    nix-direnv = {
      url = "github:nix-community/nix-direnv";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    # Stylix
    stylix = {
      url = "github:danth/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        flake-compat.follows = "flake-compat";
      };
    };

    # VS Code
    vscode-insider = {
      url = "github:iosmanthus/code-insiders-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
        flake-utils.follows = "flake-utils";
      };
    };

    # Nix gaming
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
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

    # Nix Minecraft
    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    # Geospatial Nix
    geospatial-nix = {
      url = "github:imincik/geospatial-nix";
    };

  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org" # official nix cache
      "https://nixpkgs-wayland.cachix.org" # automated builds of wayland packages
      "https://cache.privatevoid.net" # for nix-super
      "https://nix-community.cachix.org" # nix-community cache
      "https://hyprland.cachix.org" # hyprland
      "https://nixpkgs-unfree.cachix.org" # unfree-package cache
      "https://numtide.cachix.org" # another unfree package cache
      "https://cache.garnix.io" # garnix binary cache
      "https://geonix.cachix.org" # geospatial nix
    ];

    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "cache.privatevoid.net:SErQ8bvNWANeAvtsOESUwVYr2VJynfuc9JRwlzTTkVg="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };
}
