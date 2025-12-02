{
  config,
  lib,
  pkgs,
  ...
}:
{
  username,
  homeDirectory ? "/Users/${username}",
  description,
  isHidden ? false,
  createHome ? true,
  knownUser ? false,
  uid ? null,
  homeManagerModules ? (_: [ ]),
  shell ? null, # main shell package
}:
let
  shells = {
    bash = pkgs.bashInteractive;
    inherit (pkgs) zsh;
    inherit (pkgs) fish;
    inherit (pkgs) nushell;
  };

  systemFilteredShells = lib.attrsets.filterAttrs (
    shellName: _shellPkg: (builtins.hasAttr shellName config.programs)
  ) shells;
in
lib.mkMerge [
  {
    assertions = [
      {
        assertion =
          shell == null
          || (builtins.elem shell.pname (
            builtins.map (shellPkg: shellPkg.pname) (builtins.attrValues shells)
          ));
        message =
          let
            shellType = builtins.typeOf shell;
            isSet = shellType == "set";
            hasPname = if isSet then shell ? pname else false;
            shellName = if hasPname then shell.pname else "Error: not of type package";
          in
          "Invalid shell package specified: '${shellName}'";
      }
    ];
  }

  {
    users = {
      knownUsers = lib.mkIf knownUser [ username ];
      users.${username} = {
        inherit
          description
          createHome
          isHidden
          shell
          ;
        uid = lib.mkIf (
          builtins.elem username config.users.knownUsers && uid != null
        ) uid;
        home = lib.mkForce homeDirectory;
      };
    };

    # enable the shell package if it exists
    programs = builtins.mapAttrs (_shellName: shellPkg: {
      enable = lib.mkIf (shellPkg.pname == shell.pname) true;
    }) systemFilteredShells;

    environment.shells = (builtins.attrValues shells) ++ [
      "/etc/profiles/per-user/${username}/bin/${shell.meta.mainProgram}"
    ];
  }

  (lib.mkIf (builtins.hasAttr "home-manager" config) {
    home-manager.users.${username} =
      let
        darwinConfig = config;
      in
      {
        lib,
        pkgs,
        config,
        ...
      }@args:
      {
        # import home-manager modules and resolve function
        # NOTE: withTreeModules shouldn't cause issues if tree modules aren't used
        imports = lib.cust.withTreeModules (
          homeManagerModules (args // { inherit pkgs; })
        );
      }
      // lib.mkMerge [
        {
          # Use the same nix package as nixos
          nix.package = lib.mkIf darwinConfig.nix.enable (
            lib.mkForce darwinConfig.nix.package
          );

          # Set default settings based on the system settings
          home = {
            username = lib.mkForce username;
            homeDirectory = lib.mkForce homeDirectory;
          };
        }

        # TODO: move to a separate module that can be used or not used
        {
          # Allow HM to manage itself when in standalone mode.
          # This makes the home-manager command available to users.
          programs.home-manager.enable = true;

          # Disable home-manager man-pages to save space
          manual = {
            manpages.enable = false;
            html.enable = false;
            json.enable = false;
          };
        }

        (
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

            home = {
              sessionVariables = builtins.mapAttrs (
                _VAR: value: lib.mkDefault value
              ) darwinConfig.environment.variables;

              shell =
                let
                  # function to capitalize the first letter in a string
                  capitalize =
                    str:
                    lib.strings.toUpper (builtins.substring 0 1 str)
                    + builtins.substring 1 (builtins.stringLength str) str;
                in
                {
                  # Disable global shell integration
                  enableShellIntegration = false;
                }
                // builtins.listToAttrs (
                  lib.mapAttrsToList (
                    shellName: shellPkg:
                    lib.nameValuePair "enable${capitalize shellName}Integration" (
                      lib.mkIf (
                        (shellPkg.pname == shell.pname) || config.programs."${shellName}".enable
                      ) true
                    )
                  ) shells
                );
            };
          }
        )
        {
          home.sessionVariables = {
            # Set the default shell to the one specified in the config
            SHELL = lib.mkIf (shell != null) (
              lib.mkDefault "/run/current-system/sw/bin/${shell.meta.mainProgram}"
            );
          };
        }
      ];
  })
]
