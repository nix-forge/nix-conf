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

        # PerSystem attributes that are built for each system.
        perSystem =
          { pkgs, ... }:
          let
            inherit (inputs.self) lib;
            inherit (lib.cust.files) importDirRec;

            pkg_funcs = importDirRec ./pkgs [ ];

            mkPkgs = import inputs.nixpkgs {
              system = pkgs.system;
              config.allowUnfree = true;
            };

            # import the dependencies for each package
            packages = builtins.mapAttrs (name: value: mkPkgs.callPackage value { }) pkg_funcs;
          in
          {
            inherit packages;
          };

        flake =
          let
            inherit (inputs.self) lib;
            inherit (lib.cust.builders) mkHost;
            inherit (lib.cust.files) importDirRec;
          in
          {
            # Entry-point for NixOS configurations.
            nixosConfigurations =
              let
                hostDir = ./hosts;
                excludes = [ ];
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

    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # TODO: remove reliance on this as it makes config confusing
    bird-nix-lib = {
      url = "github:spikespaz/bird-nix-lib";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
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

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

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
      url = "github:Gerg-L/spicetify-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };

    # Nix Language Server
    nixd = {
      url = "github:nix-community/nixd";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
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
        flake-utils.follows = "flake-utils";
        systems.follows = "systems";
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

    # Firefox Arkenfox
    firefox-arkenfox = {
      url = "github:arkenfox/user.js";
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

    # Geospatial Nix
    geospatial-nix = {
      url = "github:imincik/geospatial-nix";
      inputs = {
        flake-compat.follows = "flake-compat";
        flake-utils.follows = "flake-utils";
        # Don't import nixpkgs as this could cause cache miss
      };
    };

    # Nixvim
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";

        # Optional
        home-manager.follows = "home-manager";
        treefmt-nix.follows = "treefmt-nix";
        flake-compat.follows = "flake-compat";

        nuschtosSearch.follows = "";
        nix-darwin.follows = "";
        devshell.follows = "";
        git-hooks.follows = "";
      };
    };

    # Cosmic Desktop
    cosmic = {
      url = "github:lilyinstarlight/nixos-cosmic";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org" # official nix cache
      "https://nix-community.cachix.org" # nix-community cache
      "https://hyprland.cachix.org" # hyprland
      "https://nixpkgs-unfree.cachix.org" # unfree-package cache
      "https://cache.garnix.io" # garnix binary cache
      "https://geonix.cachix.org" # geospatial nix
      "https://cosmic.cachix.org" # cosmic desktop
    ];

    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "geonix.cachix.org-1:iyhIXkDLYLXbMhL3X3qOLBtRF8HEyAbhPXjjPeYsCl0="
      "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
    ];
  };
}
