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
  allSecrets =
    if builtins.pathExists ../../secrets/default.nix then
      import ../../secrets { inherit myLib; }
    else
      {
        shared = {
          secrets = { };
        };
        users = { };
      };
  homeSecretsFor =
    homeConfig:
    if homeConfig ? secrets then
      myLib.secrets.selectSecretsForTarget {
        secretsTree = allSecrets;
        target = {
          targetId = "home:${homeConfig.username}@${homeConfig.folderName}";
          targetType = "home";
          username = homeConfig.username;
          configName = homeConfig.folderName;
          platform = null;
          groups = homeConfig.secrets.groups or [ ];
        };
      }
    else
      { };

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
      mkExtraSpecialArgs = _: homeConfig: { secrets = homeSecretsFor homeConfig; };
    };
  };
}
