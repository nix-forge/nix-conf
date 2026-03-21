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
  homeSecretsFor =
    homeConfig:
    if homeConfig ? secrets then
      myLib.secrets.selectSecretsForTarget {
        secretsTree = allSecrets;
        target = {
          targetId = "home:${homeConfig.username}@${homeConfig.folderName}";
          targetType = "home";
          inherit (homeConfig) username;
          configName = homeConfig.folderName;
          platform = null;
          groups = homeConfig.secrets.groups or [ ];
        };
      }
    else
      { };
  hostSecretsFor =
    hostConfig:
    if hostConfig ? secrets then
      myLib.secrets.selectSecretsForTarget {
        secretsTree = allSecrets;
        target = {
          targetId = "host:darwin:${hostConfig.folderName}";
          targetType = "host";
          username = null;
          configName = hostConfig.folderName;
          platform = "darwin";
          groups = hostConfig.secrets.groups or [ ];
        };
      }
    else
      { };
  homeConfigs = myLib.dir.importHomeConfigs ../../configs/home {
    inherit inputs;
    inherit (args) self;
    modules = lib.attrsets.unionOfDisjoint homeModules sharedHomeModules;
    mkHomeAttrs = _: homeConfig: { secrets = homeSecretsFor homeConfig; };
  };
in
{
  imports = [ inputs.nix-darwin.flakeModules.default ];

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
      mkSpecialArgs = _: hostConfig: { secrets = hostSecretsFor hostConfig; };
    };
  };
}
