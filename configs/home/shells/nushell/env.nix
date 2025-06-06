{ lib, config, ... }:
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
              [ rightSideVarPreset ]
              [
                ''" + (do { let x = ($env.${n}? | default ""); if $x == "" { "" } else { ":" + $x } }) | split row (char esep) | uniq''
              ]
              v;
        in
        lib.pipe v [
          (replaceVars [ "$HOME" "$USER" ] [ config.home.username config.home.homeDirectory ])
          replaceVarPresets
        ]
      ) vars
    );
in
{
  programs.nushell.extraEnv = lib.mkBefore ''
    ${exportToNuEnv config.home.sessionVariables}
  '';
}
