{
  lib,
  myLib,
  config,
  withSystem,
  inputs,
  ...
}@args:
let
  nixosModules = myLib.dir.importFlatWithDirs ../../modules/nixos { sep = "-"; };
  sharedModules = myLib.dir.importSharedFlat ../../modules/shared {
    class = "nixos";
    sep = "-";
    inherit args;
  };
  modules = config.flake.modules.nixos;
in
{
  flake = {
    modules.nixos = lib.attrsets.unionOfDisjoint nixosModules sharedModules;
    nixosModules = modules;

    nixosConfigurations = myLib.dir.importHosts ../../configs/nixos {
      inherit modules withSystem inputs;
      inherit (args) self;
      inherit (myLib.configs) mkHost;
      builder = lib.nixosSystem;
    };
  };
}
