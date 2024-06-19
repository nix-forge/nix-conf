{
  description = "Ian's Nix Configuration";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, ... }:
      {
        # Systems for which the attributes of `perSystem` will be built
        # add more if they can be supported...
        #  - x86_64-linux: Desktops, laptops, servers
        #  - aarch64-linux: ARM-based devices, PoC server and builders
        #  - ...
        systems = import inputs.systems;

        # Imports for constructing a final flake to be built.
        imports = [
          # Imported
          # inputs.flake-parts.flakeModules.easyOverlay

          # Explicitly import parts of the flake, which allows me to build the
          # "final flake" from various parts, arranged in a way that makes
          # sense to me the most. By convention, things that would usually
          # go to flake.nix should have its own file in the `flake/` directory.
          # ./flake/apps # apps provided by the flake
          ./flake/checks # checks that are performed on `nix flake check`
          ./flake/lib # extended library on top of `nixpkgs.lib`
          ./flake/tree.nix # tree structure of the flake that imports leafs (files)
          # ./flake/modules # nixos and home-manager modules provided by this flake
          # ./flake/pkgs # packages exposed by the flake
          # ./flake/pre-commit # pre-commit hooks, performed before each commit inside the devShell
          # ./flake/templates # flake templates

          # ./flake/args.nix # args that are passed to the flake, moved away from the main file
          # ./flake/deployments.nix # deploy-rs configurations for active hosts
          ./flake/fmt.nix # various formatter configurations for this flake
          # ./flake/iso-images.nix # local installation media
          # ./flake/shell.nix # devShells exposed by the flake
        ];

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
            nixOSModules = tree._nixOSModules;

            # Home Manager Modules
            homeManagerModules = tree._homeModules;
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
      ref = "refs/tags/v0.41.0";
      submodules = true;
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
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://cache.privatevoid.net"
    ];

    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "cache.privatevoid.net:SErQ8bvNWANeAvtsOESUwVYr2VJynfuc9JRwlzTTkVg="
      "notashelf.cachix.org-1:VTTBFNQWbfyLuRzgm2I7AWSDJdqAa11ytLXHBhrprZk="
    ];
  };
}
