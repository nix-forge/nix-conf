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
      sshPubKey ? null,
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
            sshPubKey
            ;
          configName = "${username}@${args.folderName}";
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
      inputs.home-manager.lib.homeManagerConfiguration { inherit pkgs modules extraSpecialArgs; }
    );

  connectHome =
    {
      homeConfig,
      username ? homeConfig.username,
      homeDirectory ? homeConfig.homeDirectory,
      uid ? homeConfig.uid,
      sshPubKey ? homeConfig.sshPubKey or null,
      extraModules ? [ ],
    }:
    {
      ${username} =
        { lib, ... }:
        {
          _module.args = {
            inherit sshPubKey;
            configFolderName = homeConfig.folderName;
            configName = "${username}@${homeConfig.folderName}";
          };
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
      description,
      username ? null,
      homeDirectory ? null,
      uid ? null,
      sshPubKey ? null,
      isHidden ? false,
      createHome ? true,
      knownUser ? false,
      shell ? null,
    }:
    let
      extraModules =
        _systemConfig:
        singleton (
          { lib, ... }:
          {
            fonts.fontconfig.enable = lib.mkForce false;
          }
        );
    in
    {
      pkgs,
      config,
      homeConfigs,
      ...
    }:
    let
      homeConfig = homeConfigs.${configName};
      args = {
        username = if username != null then username else homeConfig.username;
        homeDirectory = if homeDirectory != null then homeDirectory else homeConfig.homeDirectory;
        uid = if uid != null then uid else homeConfig.uid;
        sshPubKey = if sshPubKey != null then sshPubKey else homeConfig.sshPubKey or null;
      };
      shells = {
        bash = pkgs.bashInteractive;
        inherit (pkgs) zsh;
        inherit (pkgs) fish;
        inherit (pkgs) nushell;
      };
    in
    {
      users = {
        knownUsers = lib.mkIf knownUser [ args.username ];
        users.${args.username} = {
          inherit
            description
            createHome
            isHidden
            shell
            ;
          uid = lib.mkIf (knownUser && args.uid != null) args.uid;
          home = lib.mkForce args.homeDirectory;
        };
      };
      environment.shells =
        (builtins.attrValues shells)
        ++ lib.optionals (shell != null) [
          "/etc/profiles/per-user/${args.username}/bin/${shell.meta.mainProgram}"
        ];
      home-manager.users = lib.mkMerge [
        (connectHome {
          inherit homeConfig;
          inherit (args) username homeDirectory uid;
          inherit (args) sshPubKey;
          extraModules = extraModules config;
        })
        {
          ${username} =
            let
              homeFilteredShells = lib.attrsets.filterAttrs (
                shellName: _shellInfo: (builtins.hasAttr shellName config.programs)
              ) shells;
            in
            {
              programs = builtins.mapAttrs (
                _shellName: shellPkg:
                (lib.mkIf (shellPkg.pname == shell.pname) {
                  enable = true;
                  package = shell;
                })
              ) homeFilteredShells;

              home.sessionVariables = builtins.mapAttrs (
                _VAR: value: lib.mkDefault value
              ) config.environment.variables;
            };
        }
      ];
    };

  connectHomeNixos =
    configName:
    {
      username ? null,
      homeDirectory ? null,
      uid ? null,
      sshPubKey ? null,
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
        homeDirectory = if homeDirectory != null then homeDirectory else homeConfig.homeDirectory;
        uid = if uid != null then uid else homeConfig.uid;
        sshPubKey = if sshPubKey != null then sshPubKey else homeConfig.sshPubKey;
      };
    in
    {
      home-manager.users = connectHome {
        inherit homeConfig;
        inherit (args) username homeDirectory uid;
        inherit (args) sshPubKey;
        extraModules = extraModules config;
      };
    };
}
