{
  description = "A small, independent Home Manager configuration and NixOS practice VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      homes = forAllSystems (
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
        }
      );
      vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          ./vm.nix
          ({ modulesPath, ... }: {
            imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
          })
        ];
      };
    in
    {
      homeConfigurations = homes;
      packages = forAllSystems (
        system:
        {
          default = homes.${system}.activationPackage;
          home-manager = home-manager.packages.${system}.home-manager;
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          vm = vm.config.system.build.vm;
        }
      );
      checks = forAllSystems (
        system:
        {
          home = homes.${system}.activationPackage;
          generated-config = import ./tests/generated-config.nix {
            pkgs = nixpkgs.legacyPackages.${system};
            home = homes.${system};
          };
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          vm-runtime = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
            name = "public-starter";
            nodes.machine = {
              imports = [
                home-manager.nixosModules.home-manager
                ./vm.nix
              ];
            };
            testScript = import ./tests/vm.nix;
          };
        }
      );
    };
}
