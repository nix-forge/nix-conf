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
  homeModules = myLib.dir.importFlatWithDirs ../../modules/home { sep = "-"; };
  sharedHomeModules = myLib.dir.importSharedFlat ../../modules/shared {
    class = "homeManager";
    sep = "-";
    inherit args;
  };
  homeConfigs = myLib.dir.importHomeConfigs ../../configs/home {
    inherit inputs;
    inherit (args) self;
    modules = lib.attrsets.unionOfDisjoint homeModules sharedHomeModules;
  };
in
{
  flake = {
    modules.nixos = lib.attrsets.unionOfDisjoint nixosModules sharedModules;
    nixosModules = modules;

    nixosConfigurations = myLib.dir.importHosts ../../configs/nixos {
      inherit modules homeConfigs;
      inherit withSystem inputs;
      inherit (args) self;
      inherit (myLib.configs) mkHost;
      inherit (myLib.configs) connectHomeDarwin connectHomeNixos;
      builder = lib.nixosSystem;
      extraSpecialArgs = { inherit myLib; };
    };
  };
}
