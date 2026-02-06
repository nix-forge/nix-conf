{ lib, ... }:
let
  inherit (lib) concatLists singleton;
in
rec {
  # Build a standalone Home Manager configuration
  #
  # Mirrors mkHost but produces a homeManagerConfiguration instead of a system.
  # Each home config directory should have a default.nix that returns:
  #   { system, username, homeDirectory, modules, stateVersion?, nixpkgsArgs?, extraSpecialArgs? }
  #
  # Type: { withSystem, inputs, self } -> HomeSpec -> HomeManagerConfiguration
  mkHome =
    {
      withSystem,
      inputs,
      self,
    }:
    {
      system,
      username,
      homeDirectory,
      uid,
      ...
    }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        pkgs = import inputs.nixpkgs ({ inherit system; } // (args.nixpkgsArgs or { }));

        extraSpecialArgs = {
          inherit
            inputs'
            self'
            inputs
            self
            system
            ;
        }
        // (args.extraSpecialArgs or { });

        modules = concatLists [
          (singleton {
            home = {
              username = lib.mkForce username;
              homeDirectory = lib.mkForce homeDirectory;
              uid = lib.mkForce uid;
            };
            programs.home-manager.enable = true;
          })
          (args.modules or [ ])
        ];
      in
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs modules extraSpecialArgs;
      }
    );

  connectHome =
    {
      homeConfig,
      username ? homeConfig.username,
      homeDirectory ? homeConfig.homeDirectory,
      uid ? homeConfig.uid,
      extraModules ? [ ],
    }:
    {
      ${username} =
        { lib, ... }:
        {
          imports = homeConfig.modules ++ extraModules;
          home = {
            username = lib.mkForce username;
            homeDirectory = lib.mkForce homeDirectory;
            uid = lib.mkForce uid;
          };
          nix.package = lib.mkForce null;
          programs.home-manager.enable = true;
        };
    };

  connectHomeDarwin =
    configName:
    {
      username ? null,
      homeDirectory ? null,
      uid ? null,
    }:
    let
      extraModules =
        systemConfig:
        singleton (
          { lib, ... }:
          {
            fonts.fontconfig.enable = lib.mkForce false;
          }
        );
    in
    { config, homeConfigs, ... }:
    let
      homeConfig = homeConfigs.${configName};
      args = {
        username = if username != null then username else homeConfig.username;
        homeDirectory =
          if homeDirectory != null then homeDirectory else homeConfig.homeDirectory;
        uid = if uid != null then uid else homeConfig.uid;
      };
    in
    {
      home-manager.users = connectHome {
        inherit homeConfig;
        inherit (args) username homeDirectory uid;
        extraModules = extraModules config;
      };
    };

  connectHomeNixos =
    configName:
    {
      username ? null,
      homeDirectory ? null,
      uid ? null,
    }:
    let
      extraModules =
        systemConfig:
        singleton (
          { lib, ... }:
          {
            fonts.fontconfig.enable = lib.mkForce (!systemConfig.fonts.fontconfig.enable);
          }
        );
    in
    { config, homeConfigs, ... }:
    let
      homeConfig = homeConfigs.${configName};
      args = {
        username = if username != null then username else homeConfig.username;
        homeDirectory =
          if homeDirectory != null then homeDirectory else homeConfig.homeDirectory;
        uid = if uid != null then uid else homeConfig.uid;
      };
    in
    {
      home-manager.users = connectHome {
        inherit homeConfig;
        inherit (args) username homeDirectory uid;
        extraModules = extraModules config;
      };
    };
}
