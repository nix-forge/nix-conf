{
  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

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
    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS Hardware
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      # Keep the boot-chain implementation on a released interface.  Secure
      # Boot policy and key material remain in the NixOS configuration and on
      # the physical host respectively, never in this flake input.
      url = "github:nix-community/lanzaboote/v1.1.0";
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

    # Pinned DNS blocking data. Updating this input is an explicit policy
    # review captured in flake.lock, not an unreviewed runtime list download.
    stevenblack-hosts = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };
  };

  outputs =
    inputs:
    let
      myLib = import ./lib { inherit (inputs.nixpkgs) lib; };
      # Public repository trust anchors. Private age identities and signing
      # keys remain outside this repository and outside the Nix store.
      nixSealCatalog = {
        administrators.ianhollow = {
          identities = {
            administrator = {
              kind = "administrator";
              public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
            };
            recovery = {
              kind = "recovery";
              public = "age12h383letjnn5sag0799ssvfz94n83mwvcfcv87lkj379y0c65d0ss2t559";
            };
            release = {
              kind = "signer";
              public = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
            };
            delegated-create = {
              # This public key may issue only short-lived, create-only
              # capabilities for Nix-declared pending secrets. Its private
              # key is stored outside the repository and Nix store.
              kind = "authorizer";
              public = "nix-seal-ed25519-v1:Izzr/Ats9t9oXkXLl7+WotqnPeGdRhQdiR/i7Xlym2k=";
            };
          };
          approvalPolicies.release = {
            threshold = 1;
            signers = [ "release" ];
          };
          defaultApprovalPolicy = "release";
        };
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
        inputs.nix-seal.flakeModules.nix-config-framework
        ./flake/partitions.nix
        ./flake/deploy.nix
        ./flake/schemas.nix
      ];

      _module.args.myLib = myLib;

      flake.nixSeal = nixSealCatalog;

      nixConfigFramework = {
        root = ./.;
        extraSpecialArgs = { inherit myLib; };
      };

      perSystem = { system, ... }: { packages = inputs.nixpkgs-personal.packages.${system}; };
    };
}
