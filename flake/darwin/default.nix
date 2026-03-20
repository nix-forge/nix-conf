{
  inputs,
  lib,
  myLib,
  config,
  withSystem,
  ...
}@args:
let
  darwinModules = myLib.dir.importFlatWithDirs ../../modules/darwin { sep = "-"; };
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
  allSecrets =
    if builtins.pathExists ../../secrets/default.nix then
      import ../../secrets { inherit myLib; }
    else
      {
        shared = {
          secrets = { };
        };
        systems = { };
        users = { };
      };
  secretsFor =
    configData:
    if configData ? secrets then
      myLib.secrets.selectSecretsForTarget {
        secretsTree = allSecrets;
        target = {
          targetId = "host:darwin:${configData.folderName}";
          targetType = "host";
          username = null;
          configName = configData.folderName;
          platform = "darwin";
          groups = configData.secrets.groups or [ ];
        };
      }
    else
      { };
  homeConfigs = myLib.dir.importHomeConfigs ../../configs/home {
    inherit inputs;
    inherit (args) self;
    modules = lib.attrsets.unionOfDisjoint homeModules sharedHomeModules;
    mkHomeAttrs = _: homeConfig: { secrets = secretsFor homeConfig; };
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
      mkSpecialArgs = _: hostConfig: { secrets = secretsFor hostConfig; };
    };
  };
}
