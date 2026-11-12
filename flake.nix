{
  # Bootstrap caches for commands using this flake, including the first build
  # before system settings are activated. Nix requires literal settings here;
  # this list applies to every output. Installed policy is feature-dependent
  # in modules/shared/cache.nix. See docs/research/nix-caches-research.md.
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://cache.nixos-cuda.org"
      "https://noctalia.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    self.submodules = true;

    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Use maintained application recipes without changing the system package set.
    nixpkgs-apps = {
      url = "github:NixOS/nixpkgs/b3cff76391a4867236cc135b69a928d873b9f6d0";
      flake = false;
    };
    # Track the official T3 Code package without downgrading existing app data.
    nixpkgs-t3code = {
      url = "github:NixOS/nixpkgs/master";
      flake = false;
    };
    systems.url = "github:nix-systems/default";
    nixpkgs-personal = {
      url = "path:./pkgs";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        pre-commit-hooks.inputs.flake-compat.follows = "flake-compat";
      };
    };
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        hyprgraphics.follows = "hyprland/hyprgraphics";
        hyprlang.follows = "hyprland/hyprlang";
        hyprutils.follows = "hyprland/hyprutils";
        hyprwayland-scanner.follows = "hyprland/hyprwayland-scanner";
      };
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0";
    nix-config-framework = {
      url = "path:./nix-config-framework";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        flake-schemas.follows = "flake-schemas";
        home-manager.follows = "home-manager";
        nix-darwin.follows = "nix-darwin";
      };
    };
    nix-seal = {
      url = "path:./nix-seal";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        flake-schemas.follows = "flake-schemas";
        home-manager.follows = "home-manager";
        nix-darwin.follows = "nix-darwin";
      };
    };
    nix-homelab = {
      url = "path:./nix-homelab";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-apps.follows = "nixpkgs-apps";
        nixpkgs-personal.follows = "nixpkgs-personal";
        flake-parts.follows = "flake-parts";
        git-hooks-nix.inputs.flake-compat.follows = "flake-compat";
      };
    };
    determinate = {
      url = "github:DeterminateSystems/determinate";
      inputs = {
        nix.inputs = {
          flake-parts.follows = "flake-parts";
          git-hooks-nix.inputs.flake-compat.follows = "flake-compat";
        };
      };
    };

    # Package Libraries
    nix4vscode = {
      url = "github:nix-community/nix4vscode";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tools
    stylix = {
      url = "github:nix-community/stylix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
      };
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS Hardware
    # Keep the Pi kernel and firmware on the vendor's tested, cached pin.
    # The Pi NixOS system itself uses the root nixpkgs input, like desktop.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      # This pinned upstream revision retains the booted generation and the
      # previous bootloader measurement during an update. Both repairs are
      # newer than v1.2.0; review a release before moving off this commit.
      url = "github:nix-community/lanzaboote/c57a9234747eea6fe498d0eb601583f7ba378f06";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pre-commit.inputs.flake-compat.follows = "flake-compat";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    helium-browser = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helium-browser-darwin = {
      url = "github:schembriaiden/helium-browser-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.inputs.systems.follows = "systems";
    };

    # Dependency Override
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };

    # Pinned DNS blocking data. Updating this input is an explicit policy
    # review captured in flake.lock, not an unreviewed runtime list download.
    stevenblack-hosts = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };
  };

  outputs =
    upstreamInputs:
    let
      inputs = import ./overlays/inputs.nix { inputs = upstreamInputs; };
      myLib = import ./lib { inherit (inputs.nixpkgs) lib; };

    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import ./flake/supported-systems.nix;
      imports = [
        ./flake/build-platform.nix
        inputs.nix-config-framework.flakeModules.default
        inputs.nix-seal.flakeModules.default
        inputs.nix-seal.flakeModules.nix-config-framework
        ./flake/partitions.nix
        ./flake/documentation.nix
        ./flake/public-guide.nix
        ./hosts/shared/local/flake/validation.nix
        ./hosts/shared/local/flake/development-tools.nix
        ./flake/storage.nix
        ./flake/feature-catalog.nix
        ./flake/lint-checks.nix
        ./hosts/shared/local/flake/nix-seal.nix
        ./hosts/shared/local/flake/deploy.nix
        ./hosts/shared/local/flake/raspberry-pi.nix
        ./hosts/shared/local/flake/desktop-installer.nix
        ./flake/schemas.nix
      ];

      flake.lib.packagesFor = platform: inputs.nixpkgs-personal.lib.packagesFor platform;
      flake.lib.nixosConfigurationFor =
        { name, buildSystem }:
        inputs.self.nixosConfigurations.${name}.extendModules {
          modules = [ ({ lib, ... }: { nixpkgs.buildPlatform = lib.mkForce buildSystem; }) ];
        };
      _module.args.myLib = myLib;
      # Development partitions may replace tooling inputs. Configuration
      # fixtures must retain the inputs used by the deployed configurations.
      _module.args.configurationInputs = inputs;

      nixConfigFramework = {
        root = ./.;
        extraSpecialArgs = { inherit myLib; };
      };

      perSystem = { system, ... }: { packages = inputs.nixpkgs-personal.packages.${system}; };
    };
}
