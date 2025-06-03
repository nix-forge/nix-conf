{ lib, config, ... }:
{
  programs.nushell.extraEnv =
    let
      exportToNuEnv =
        vars:
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            n: v:
            let
              replaceVars =
                varsIn: varsOut: v:
                "$env.${n} = ${
                  if lib.typeOf v == "string" then
                    "\"${builtins.replaceStrings varsIn varsOut v}\""
                  else
                    builtins.toString v
                }";
              replaceVarPresets =
                v:
                let
                  rightSideVarPreset = lib.concatStrings [
                    "$"
                    "{"
                    n
                    ":+:$"
                    n
                    "}"
                    "\""
                  ];
                in
                builtins.replaceStrings
                  [
                    rightSideVarPreset
                  ]
                  [
                    ''" + (do { let x = ($env.${n}? | default ""); if $x == "" { "" } else { ":" + $x } }) | split row (char esep) | uniq''
                  ]
                  v;
            in
            lib.pipe v [
              (replaceVars
                [
                  "$HOME"
                  "$USER"
                ]
                [ config.home.username config.home.homeDirectory ]
              )
              replaceVarPresets
            ]
          ) vars
        );

      paths =
        [
          config.home.profileDirectory
        ]
        ++ lib.optionals (args ? darwinConfig) args.darwinConfig.environment.profiles
        ++ lib.optionals (args ? nixosConfig) args.nixosConfig.environment.profiles;

      binPaths = lib.pipe paths [
        (builtins.map (p: "${p}/bin"))
        (builtins.map (
          builtins.replaceStrings
            [ "$USER" "$HOME" "\${XDG_STATE_HOME}" ]
            [ config.home.username config.home.homeDirectory config.xdg.stateHome ]
        ))
      ];

      esepDirListToList = var: ''
        "${var}": {
          from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
          to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
        }
      '';
    in
    lib.mkBefore (
      ''
        ${exportToNuEnv config.home.sessionVariables}

        $env.ENV_CONVERSIONS = {
          ${esepDirListToList "TERMINFO_DIRS"}
          ${esepDirListToList "XDG_CONFIG_DIRS"}
          ${esepDirListToList "XDG_DATA_DIRS"}
          ${esepDirListToList "XCURSOR_PATH"}
        }
      ''
      + ''
        $env.PATH = $env.PATH | split row (char esep) | prepend [
          ${lib.concatStringsSep "\n" (
            (lib.optionals (args ? nixosConfig) [ "/run/wrappers/bin" ]) ++ config.home.sessionPath ++ binPaths
          )}
        ] | uniq
      ''
    );
}
