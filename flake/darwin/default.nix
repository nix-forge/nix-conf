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
  allSecrets = import ../../secrets { inherit myLib; };
  homeSecretsFor =
    username:
    allSecrets.shared.secrets
    // (if allSecrets.users ? ${username} then allSecrets.users.${username}.secrets else { });
  systemSecretsFor =
    configName:
    allSecrets.shared.secrets
    // (
      if allSecrets.systems ? darwin && allSecrets.systems.darwin ? configName then
        allSecrets.systems.darwin.${configName}.secrets
      else
        { }
    );
  homeConfigs = myLib.dir.importHomeConfigs ../../configs/home {
    inherit inputs;
    inherit (args) self;
    modules = lib.attrsets.unionOfDisjoint homeModules sharedHomeModules;
    mkHomeAttrs = _: homeConfig: { secrets = homeSecretsFor homeConfig.username; };
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
      mkSpecialArgs = entry: _: { secrets = systemSecretsFor (myLib.dir.entryAttrName entry); };
    };
  };
}
