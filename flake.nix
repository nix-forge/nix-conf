{
  description = "Ian's Nix Configuration";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, tree, ... }:
      {
        imports = [
          ./flake
          ./lib
        ];

        flake =
          let
            inherit (inputs.self) lib;
            inherit (lib.cust.builders) mkHost mkDarwin;
            inherit (lib.cust.files) importDirRec;

            hostConfigsDir = ./hosts;
            excludes = [ ];
            hostConfigs = importDirRec hostConfigsDir excludes;

            baseConfigParams = folderName: {
              inherit withSystem;
              inherit inputs;
              inherit (inputs) self determinate;
              inherit (inputs.self) lib;
              inherit tree;
              inherit folderName;
            };

            configParameterize =
              folderName: configDef:
              lib.pipe folderName [
                baseConfigParams
                (x: (configDef x) // x)
              ];

            isSystem =
              systemTypes: finalConfigParams:
              lib.pipe finalConfigParams [
                (builtins.getAttr "system")
                (lib.splitString "-")
                (x: lib.flip lib.elemAt ((builtins.length x) - 1) x)
                (lib.flip builtins.elem systemTypes)
              ];

            mkConfig =
              builder: systemTypes:
              lib.pipe hostConfigs [
                (lib.mapAttrs configParameterize)
                (lib.filterAttrs (_: isSystem systemTypes))
                (lib.mapAttrs (_: builder))
              ];
          in
          {
            # Entry-point for NixOS configurations.
            nixosConfigurations = mkConfig mkHost [ "linux" ];

            # Entry point for Darwin configurations.
            darwinConfigurations = mkConfig mkDarwin [ "darwin" ];

            # NixOS modules (standard key)
            nixosModules = lib.cust.files.importDirFlat ./nixosModules {
              filter = [ ];
              importDirDefault = true;
              sep = "-";
            };
          };
      }
    );

  inputs = {
    # Systems
    systems.url = "github:nix-systems/default";

    # Latest Nixpkgs Unstable
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";

    # Determinate
    nix = {
      url = "github:DeterminateSystems/nix-src";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-23-11.follows = "";
        flake-parts.follows = "flake-parts";
        git-hooks-nix.follows = "git-hooks";
      };
    };
    determinate = {
      url = "github:DeterminateSystems/determinate";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix.follows = "nix";
      };
    };

    # Flake Parts
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Latest Home Manager
    # TODO: look into using https://github.com/nix-community/home-manager/pull/7970
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-Darwin
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Git Hooks
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };

    # Nix Secrets (from personal private repo)
    nix-secrets = {
      url = "github:IanHollow/nix-secrets";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur-rycee = {
      url = "sourcehut:~rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    flake-compat.url = "github:edolstra/flake-compat";

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
        systems.follows = "systems";
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
      # url = "github:IanHollow/stylix/vscode-improve-theme";
      # url = "git+file:///Users/ianmh/Projects/personal/stylix";
      url = "github:nix-community/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
      };
    };

    # VS Code
    vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    # Nix gaming
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs = {
        flake-parts.follows = "flake-parts";
        # Don't overwrite nixpkgs as this could cause cache miss
      };
    };
    nix-gaming-custom = {
      url = "github:IanHollow/nix-gaming";
      inputs = {
        flake-parts.follows = "flake-parts";
        # Don't overwrite nixpkgs as this could cause cache miss
      };
    };

    # Firefox BetterFox
    # TODO: use a package instead of a flake
    firefox-betterfox = {
      url = "github:yokoffing/Betterfox";
      flake = false;
    };

    # Firefox UI Fix
    # TODO: use a package instead of a flake
    firefox-ui-fix = {
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

    # Nixvim
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs = {
        systems.follows = "systems";
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    # Cosmic Desktop
    cosmic = {
      url = "github:lilyinstarlight/nixos-cosmic";
      inputs = {
        flake-compat.follows = "flake-compat";
        nixpkgs.follows = "nixpkgs";
      };
    };

    # Hyprland Flake
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        pre-commit-hooks.follows = "git-hooks";
      };
    };

    hyprpaper = {
      url = "github:hyprwm/hyprpaper";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    # AMD microcode updates
    ucodenix.url = "github:e-tho/ucodenix";

    # Agenix
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        systems.follows = "systems";
        nixpkgs.follows = "nixpkgs";
        darwin.follows = "nix-darwin";
        home-manager.follows = "home-manager";
      };
    };

    # Ags
    # ags = {
    #   url = "github:Aylur/ags";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.astal.follows = "astal";
    # };
    # astal = {
    #   url = "github:Aylur/astal";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    auto-cpufreq = {
      url = "github:AdnanHodzic/auto-cpufreq";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org" # official nix cache
      "https://nix-community.cachix.org" # nix-community cache
      "https://nixpkgs-unfree.cachix.org" # unfree-package cache
      "https://cache.garnix.io" # garnix binary cache
      "https://geonix.cachix.org" # geospatial nix
      "https://nix-gaming.cachix.org" # nix-gaming cache
      "https://cosmic.cachix.org" # cosmic desktop
      "https://hyprland.cachix.org" # hyprland cache
      "https://nixpkgs-wayland.cachix.org" # nixpkgs wayland cache
    ];

    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "geonix.cachix.org-1:iyhIXkDLYLXbMhL3X3qOLBtRF8HEyAbhPXjjPeYsCl0="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
    ];
  };
}
