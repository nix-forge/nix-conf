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
      let
        configName = hostConfig.folderName or hostConfig.hostName or "unknown";
      in
      myLib.secrets.selectSecretsForTarget {
        secretsTree = allSecrets;
        target = {
          targetId = "host:nixos:${configName}";
          targetType = "host";
          username = null;
          inherit configName;
          platform = "nixos";
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
      mkSpecialArgs = _: hostConfig: { secrets = hostSecretsFor hostConfig; };
    };

    deploy.nodes =
      if lib.hasAttr "server" config.flake.nixosConfigurations then
        {
          server = {
            hostname = "server";
            sshUser = "root";
            profilesOrder = [ "system" ];
            profiles.system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos config.flake.nixosConfigurations.server;
            };
          };
        }
      else
        { };
  };
}
