{
  description = "Ian's Nix Configuration";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, ... }:
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
              inherit (inputs.self) lib tree;
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

            # Home Manager Modules
            homeManagerModules = importDirRec ./_homeModules [ ];
          };
      }
    );

  inputs = {
    # Systems
    systems.url = "github:nix-systems/default";

    # Latest Nixpkgs Unstable
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Determinate
    determinate.url = "github:DeterminateSystems/determinate";

    # Flake Parts
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Latest Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-Darwin
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mac-app-util = {
      url = "github:hraban/mac-app-util";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
        flake-utils.follows = "flake-utils";
      };
    };

    # Git Hooks
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };

    # Nix Secrets (from personal private repo)
    nix-secrets = {
      url = "git+ssh://git@github.com/IanHollow/nix-secrets.git?ref=main&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NUR
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    flake-utils.url = "github:numtide/flake-utils";

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
      url = "github:danth/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        nur.follows = "nur";
      };
    };

    # VS Code
    vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
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

    # Firefox BetterFox
    # TODO: use a package instead of a flake
    firefox-betterfox = {
      url = "github:yokoffing/Betterfox";
      flake = false;
    };

    # Firefox Arkenfox
    # TODO: use a package instead of a flake
    firefox-arkenfox = {
      url = "github:arkenfox/user.js";
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

    # Provide NixGL for Geospatial Nix
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    # Geospatial Nix
    geospatial-nix = {
      url = "github:imincik/geospatial-nix";
      inputs = {
        flake-compat.follows = "flake-compat";
        flake-utils.follows = "flake-utils";
        nixgl.follows = "nixgl";

        # Don't overwrite nixpkgs as this could cause cache miss
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
        # Don't overwrite nixpkgs as this could cause cache miss
      };
    };

    # Hyprland Flake
    aquamarine = {
      url = "github:hyprwm/aquamarine";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprutils.follows = "hyprutils";
        hyprwayland-scanner.follows = "hyprwayland-scanner";
      };
    };

    hyprcursor = {
      url = "github:hyprwm/hyprcursor";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprlang.follows = "hyprlang";
      };
    };

    hyprgraphics = {
      url = "github:hyprwm/hyprgraphics";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprutils.follows = "hyprutils";
      };
    };

    hyprland-protocols = {
      url = "github:hyprwm/hyprland-protocols";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    hyprland-qt-support = {
      url = "github:hyprwm/hyprland-qt-support";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprlang.follows = "hyprlang";
      };
    };

    hyprland-qtutils = {
      url = "github:hyprwm/hyprland-qtutils";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprlang.follows = "hyprlang";
        hyprutils.follows = "hyprutils";
        hyprland-qt-support.follows = "hyprland-qt-support";
      };
    };

    hyprlang = {
      url = "github:hyprwm/hyprlang";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprutils.follows = "hyprutils";
      };
    };

    hyprutils = {
      url = "github:hyprwm/hyprutils";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    hyprwayland-scanner = {
      url = "github:hyprwm/hyprwayland-scanner";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };

    xdph = {
      url = "github:hyprwm/xdg-desktop-portal-hyprland";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprland-protocols.follows = "hyprland-protocols";
        hyprlang.follows = "hyprlang";
        hyprutils.follows = "hyprutils";
        hyprwayland-scanner.follows = "hyprwayland-scanner";
      };
    };

    hyprland = {
      url = "github:hyprwm/Hyprland";
      # inputs = {
      #   nixpkgs.follows = "nixpkgs";
      #   systems.follows = "systems";

      #   aquamarine.follows = "aquamarine";
      #   hyprcursor.follows = "hyprcursor";
      #   hyprgraphics.follows = "hyprgraphics";
      #   hyprland-protocols.follows = "hyprland-protocols";
      #   hyprland-qtutils.follows = "hyprland-qtutils";
      #   hyprlang.follows = "hyprlang";
      #   hyprutils.follows = "hyprutils";
      #   hyprwayland-scanner.follows = "hyprwayland-scanner";
      #   xdph.follows = "xdph";
      #   pre-commit-hooks.follows = "pre-commit-hooks";
      # };
    };

    hyprpaper = {
      url = "github:hyprwm/hyprpaper";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";

        hyprutils.follows = "hyprutils";
        hyprlang.follows = "hyprlang";
        hyprwayland-scanner.follows = "hyprwayland-scanner";
        hyprgraphics.follows = "hyprgraphics";
      };
    };

    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";

        hyprutils.follows = "hyprutils";
        hyprlang.follows = "hyprlang";
        hyprwayland-scanner.follows = "hyprwayland-scanner";
        hyprgraphics.follows = "hyprgraphics";
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

    nix-index = {
      url = "github:nix-community/nix-index";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
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
  };
}
