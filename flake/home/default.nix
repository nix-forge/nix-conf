{
  inputs,
  lib,
  myLib,
  config,
  withSystem,
  ...
}@args:
let
  homeModules = myLib.dir.importFlatWithDirs ../../modules/home { sep = "-"; };
  sharedModules = myLib.dir.importSharedFlat ../../modules/shared {
    class = "homeManager";
    sep = "-";
    inherit args;
  };

  modules = config.flake.modules.homeManager;
in
{
  imports = [ inputs.home-manager.flakeModules.home-manager ];

  flake = {
    modules.homeManager = lib.attrsets.unionOfDisjoint homeModules sharedModules;
    homeModules = config.flake.modules.homeManager;

    homeConfigurations = myLib.dir.importHomes ../../configs/home {
      inherit modules withSystem inputs;
      inherit (args) self;
      inherit (myLib.configs) mkHome;
      extraSpecialArgs = { inherit myLib; };
    };
  };
}
