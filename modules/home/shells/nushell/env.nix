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
                toString v
            }";
          replaceVarPresets =
            v:
            builtins.replaceStrings
              [ "$\\{${n}:+:$${n}}\"" ]
              [
                ''" + (do { let x = ($env.${n}? | default ""); if $x == "" { "" } else { ":" + $x } }) | split row (char esep) | uniq''
              ]
              v;
        in
        lib.pipe v [
          (replaceVars
            [ "$HOME" "$USER" ]
            [ config.home.homeDirectory config.home.username ]
          )
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
