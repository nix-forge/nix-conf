{
  inputs,
  lib,
  myLib,
  ...
}:
{
  perSystem = { system, ... }: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      public-demo-vm =
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit myLib; };
          modules = [
            inputs.home-manager.nixosModules.home-manager
            ./public-demo/graphical-vm.nix
            ({ modulesPath, ... }: { imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ]; })
          ];
        }).config.system.build.vm;
    };
  };
}
