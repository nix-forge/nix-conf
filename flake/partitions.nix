{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    nixosConfigurations = "nixos";
    nixosModules = "nixos";

    darwinConfigurations = "darwin";
    darwinModules = "darwin";

    checks = "dev";
    devShells = "dev";
    formatter = "dev";
  };

  partitions =
    let
      baseInputs = { inherit (inputs) nixpkgs home-manager; };
      homeManagerInputs = {
        inherit (inputs) nix4vscode nur-rycee;
        inherit (inputs) firefox-betterfox firefox-ui-fix;
      };
    in
    {
      nixos = {
        extraInputsFlake = ./nixos;
        module.imports = [
          ./nixos
          ./base
        ];
        extraInputs =
          baseInputs
          // {
            inherit (inputs)
              disko
              agenix
              agenix-rekey
              stylix
              ;
          }
          // homeManagerInputs;
      };

      darwin = {
        extraInputsFlake = ./darwin;
        module.imports = [
          ./darwin
          ./base
        ];
        extraInputs =
          baseInputs
          // {
            inherit (inputs)
              nix-darwin
              agenix
              agenix-rekey
              stylix
              ;
          }
          // homeManagerInputs;
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
