{ inputs, ... }:
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
          agenix
          stylix
          disko
          ;
      };
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
          agenix
          stylix
          ;
      };
    };

    home = {
      # extraInputsFlake = ./home;
      module.imports = [
        ./home
        ./base
      ];
      extraInputs = {
        inherit (inputs)
          nixpkgs
          systems
          home-manager
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
