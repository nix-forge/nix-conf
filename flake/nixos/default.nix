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
          targetId = "host:nixos:${configData.folderName}";
          targetType = "host";
          username = null;
          configName = configData.folderName;
          platform = "nixos";
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
      mkSpecialArgs = _: hostConfig: { secrets = secretsFor hostConfig; };
    };
  };
}
