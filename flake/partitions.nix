{ inputs, ... }:
let
  flake-compat = import "${inputs.flake-parts}/vendor/flake-compat";
  get-flake =
    src:
    (flake-compat {
      inherit src;
      system = throw "operating flake-compat in pure mode; system not allowed to be used";
    }).outputs;
  homeFlakeInputs = (get-flake ./home).inputs;
in
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    nixosConfigurations = "nixos";
    nixosModules = "nixos";

    darwinConfigurations = "darwin";
    darwinModules = "darwin";

    homeConfigurations = "home";
    homeModules = "home";

    checks = "dev";
    devShells = "dev";
    formatter = "dev";
  };

  partitions = {
    nixos = {
      extraInputsFlake = ./nixos;
      module.imports = [
        ./nixos
        ./base
      ];
      extraInputs = {
        inherit (inputs)
          nixpkgs
          home-manager
          nix-secrets
          agenix
          stylix
          disko
          ;
      }
      // homeFlakeInputs;
    };

    darwin = {
      extraInputsFlake = ./darwin;
      module.imports = [
        ./darwin
        ./base
      ];
      extraInputs = {
        inherit (inputs)
          nixpkgs
          nix-darwin
          home-manager
          nix-secrets
          agenix
          stylix
          ;
      }
      // homeFlakeInputs;
    };

    home = {
      extraInputsFlake = ./home;
      module.imports = [
        ./home
        ./base
      ];
      extraInputs = {
        inherit (inputs)
          nixpkgs
          home-manager
          nix-secrets
          vscode-extensions
          nur-rycee
          agenix
          stylix
          spicetify-nix
          ;
      };
    };

    dev = {
      extraInputsFlake = ./dev;
      module.imports = [
        ./dev
        ./base
      ];
    };
  };
}
