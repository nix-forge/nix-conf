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
  homeManagerModules ? ({ ... }: [ ]),
  shell ? null, # main shell package
}:
let
  shells = {
    bash = pkgs.bashInteractive;
    zsh = pkgs.zsh;
    fish = pkgs.fish;
    nushell = pkgs.nushell;
  };

  systemFilteredShells = lib.attrsets.filterAttrs (
    shellName: shellPkg: (builtins.hasAttr shellName config.programs)
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
        uid = lib.mkIf (builtins.elem username config.users.knownUsers && uid != null) uid;
        home = lib.mkForce homeDirectory;
      };
    };

    # enable the shell package if it exists
    programs = builtins.mapAttrs (shellName: shellPkg: {
      enable = lib.mkIf (shellPkg.pname == shell.pname) true;
    }) systemFilteredShells;

    environment.shells = (builtins.attrValues shells) ++ [
      "/etc/profiles/per-user/${username}/bin/${shell.meta.mainProgram}"
    ];

    environment.variables.SHELL = lib.mkIf (
      shell != null
    ) "/run/current-system/sw/bin/${shell.meta.mainProgram}";
  }

  (lib.mkIf (config ? home-manager) {
    home-manager.users.${username} =
      let
        nixosConfig = config;
      in
      {
        tree,
        lib,
        pkgs,
        inputs,
        self,
        config,
        ...
      }:
      {
        # import home-manager modules and resolve function
        # NOTE: withTreeModules shouldn't cause issues if tree modules aren't used
        imports = lib.cust.withTreeModules (homeManagerModules {
          inherit
            tree
            lib
            pkgs
            inputs
            self
            ;
        });
      }
      // lib.mkMerge [
        {
          # Use the same nix package as nixos
          nix.package = lib.mkForce nixosConfig.nix.package;

          # Allow HM to manage itself when in standalone mode.
          # This makes the home-manager command available to users.
          programs.home-manager.enable = true;

          # Disable home-manager man-pages to save space
          manual = {
            manpages.enable = false;
            html.enable = false;
            json.enable = false;
          };

          # Set default settings based on the system settings
          home = {
            username = lib.mkForce username;
            homeDirectory = lib.mkForce homeDirectory;
          };
        }

        (
          let
            homeFilteredShells = lib.attrsets.filterAttrs (
              shellName: shellInfo: (builtins.hasAttr shellName config.programs)
            ) shells;
          in
          {
            programs = builtins.mapAttrs (
              shellName: shellPkg:
              (lib.mkIf (shellPkg.pname == shell.pname) {
                enable = true;
                package = shell;
              })
            ) homeFilteredShells;

            home = {
              sessionVariables = builtins.mapAttrs (
                VAR: value: lib.mkDefault value
              ) nixosConfig.environment.variables;

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
                      lib.mkIf (shellPkg.pname == "nushell") true
                    )
                  ) shells
                );
            };
          }
        )
        {
          home.sessionVariables = {
            # Set the default shell to the one specified in the config
            SHELL = lib.mkIf (shell != null) (lib.mkDefault nixosConfig.environment.variables.SHELL);
          };
        }
      ];
  })
]
