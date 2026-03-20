{
  inputs,
  lib,
  myLib,
  ...
}@args:
let
  homeModules = myLib.dir.importFlatWithDirs ../modules/home { sep = "-"; };
  sharedHomeModules = myLib.dir.importSharedFlat ../modules/shared {
    class = "homeManager";
    sep = "-";
    inherit args;
  };
  nixosModules = myLib.dir.importFlatWithDirs ../modules/nixos { sep = "-"; };
  sharedNixosModules = myLib.dir.importSharedFlat ../modules/shared {
    class = "nixos";
    sep = "-";
    inherit args;
  };
  darwinModules = myLib.dir.importFlatWithDirs ../modules/darwin { sep = "-"; };
  sharedDarwinModules = myLib.dir.importSharedFlat ../modules/shared {
    class = "darwin";
    sep = "-";
    inherit args;
  };

  allSecrets =
    if builtins.pathExists ../secrets/default.nix then
      import ../secrets { inherit myLib; }
    else
      {
        shared = {
          secrets = { };
        };
        systems = { };
        users = { };
      };

  homeConfigs = lib.filterAttrs (name: _: builtins.match ".+@.+" name != null) (
    myLib.dir.importHomeConfigs ../configs/home {
      inherit inputs;
      inherit (args) self;
      modules = myLib.attrsets.unionOfDisjoint homeModules sharedHomeModules;
    }
  );

  nixosHostConfigs = myLib.dir.importHostConfigs ../configs/nixos {
    inherit inputs;
    inherit (args) self;
    modules = myLib.attrsets.unionOfDisjoint nixosModules sharedNixosModules;
    inherit (myLib.configs) connectHomeDarwin connectHomeNixos;
  };

  darwinHostConfigs = myLib.dir.importHostConfigs ../configs/darwin {
    inherit inputs;
    inherit (args) self;
    modules = myLib.attrsets.unionOfDisjoint darwinModules sharedDarwinModules;
    inherit (myLib.configs) connectHomeDarwin connectHomeNixos;
  };

  secretIndex = myLib.secrets.mkSecretctlIndex {
    secretsTree = allSecrets;
    inherit homeConfigs;
    hostConfigs = {
      nixos = nixosHostConfigs;
      darwin = darwinHostConfigs;
    };
  };
in
{
  flake = { inherit secretIndex; };
}
