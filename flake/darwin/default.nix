{
  inputs,
  lib,
  myLib,
  config,
  withSystem,
  ...
}@args:
let
  darwinModules = myLib.dir.importFlatWithDirs ../../modules/darwin {
    sep = "-";
  };
  sharedModules = myLib.dir.importSharedFlat ../../modules/shared {
    class = "darwin";
    sep = "-";
    inherit args;
  };
  modules = config.flake.modules.darwin;
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
  # import = [ inputs.nix-darwin.flakeModules.nix-darwin ];

  flake = {
    modules.darwin = lib.attrsets.unionOfDisjoint darwinModules sharedModules;
    darwinModules = modules;

    darwinConfigurations = myLib.dir.importHosts ../../configs/darwin {
      inherit modules homeConfigs;
      inherit withSystem inputs;
      inherit (args) self;
      inherit (myLib.configs) mkHost;
      inherit (myLib.configs) connectHomeDarwin connectHomeNixos;
      builder = inputs.nix-darwin.lib.darwinSystem;
      extraSpecialArgs = { inherit myLib; };
    };
  };
}
