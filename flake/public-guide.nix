{ inputs, lib, ... }:
{
  flake.templates.starter = {
    path = ../templates/starter;
    description = "Independent Home Manager starter with a NixOS practice VM";
    welcomeText = ''
      Build without changing your account:
        nix build .#homeConfigurations.x86_64-linux.activationPackage
      On Apple silicon, replace x86_64-linux with aarch64-darwin.
      Read README.md before adapting or activating the configuration.
    '';
  };

  flake.templates.darwin = {
    path = ../templates/darwin;
    description = "Neutral Apple silicon nix-darwin system with independent stable pins";
  };

  perSystem =
    { pkgs, system, ... }:
    {
      # These test public imports against the workstation's current inputs.
      # CI also builds templates/starter separately with its own release lockfile.
      checks.public-guide-recipes = import ../tests/public-guide/recipes.nix {
        inherit pkgs;
        inherit (inputs) home-manager;
      };
      packages = lib.optionalAttrs (system == "x86_64-linux") {
        public-demo-vm =
          (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.home-manager.nixosModules.home-manager
              ../tests/public-guide/graphical-vm.nix
              ({ modulesPath, ... }: { imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ]; })
            ];
          }).config.system.build.vm;
      };
      checks.public-demo-runtime = lib.mkIf (system == "x86_64-linux") (
        pkgs.testers.runNixOSTest {
          name = "public-graphical-demo";
          nodes.machine.imports = [
            inputs.home-manager.nixosModules.home-manager
            ../tests/public-guide/graphical-vm.nix
          ];
          testScript = import ../tests/public-guide/graphical-vm-test.nix;
        }
      );
    };
}
