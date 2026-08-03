{
  inputs = {
    self.submodules = true;

    # Core
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    nixpkgs-personal = {
      url = "path:./pkgs";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
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
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nix-config-framework = {
      url = "path:./nix-config-framework";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
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
        home-manager.follows = "home-manager";
        nix-darwin.follows = "nix-darwin";
      };
    };
    determinate = {
      url = "github:DeterminateSystems/determinate";
      inputs = {
        nix.inputs = {
          flake-parts.follows = "flake-parts";
          git-hooks-nix.follows = "git-hooks-nix";
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

    # NixOS Hardware
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Firefox UserJS
    firefox-betterfox = {
      url = "github:yokoffing/Betterfox";
      flake = false;
    };
    firefox-ui-fix = {
      url = "github:black7375/Firefox-UI-Fix";
      flake = false;
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
    };

    # Dependency Override
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      myLib = import ./lib { inherit (inputs.nixpkgs) lib; };
      # Public repository trust anchors. Private age identities and signing
      # keys remain outside this repository and outside the Nix store.
      nixSealTrust = {
        administratorRecipient = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
        recoveryRecipient = "age12h383letjnn5sag0799ssvfz94n83mwvcfcv87lkj379y0c65d0ss2t559";
        signerPublicKey = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
      };
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      imports = [
        inputs.nix-config-framework.flakeModules.default
        inputs.nix-seal.flakeModules.default
        ./flake/dev
      ];

      _module.args.myLib = myLib;

      flake.nixSealTrust = nixSealTrust;

      nixConfigFramework = {
        root = ./.;
        extraSpecialArgs = { inherit myLib nixSealTrust; };
      };

      perSystem = { system, ... }: { packages = inputs.nixpkgs-personal.packages.${system}; };
    };
}
