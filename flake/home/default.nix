{
  inputs,
  lib,
  myLib,
  config,
  ...
}@args:
let
  homeModules = myLib.dir.importFlatWithDirs ../../modules/home { sep = "-"; };
  sharedModules = myLib.dir.importSharedFlat ../../modules/shared {
    class = "homeManager";
    sep = "-";
    inherit args;
  };

in
{
  imports = [ inputs.home-manager.flakeModules.home-manager ];

  flake.modules.homeManager = lib.attrsets.unionOfDisjoint homeModules sharedModules;
  flake.homeModules = config.flake.modules.homeManager;
}
