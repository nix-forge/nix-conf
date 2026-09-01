{ lib, config, ... }:
let
  exportToNuEnv =
    vars:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        n: v:
        let
          shellVar = "$" + n;
          shellConditional = "$" + "{" + n + ":+:}";
          shellConditionalWithValue = "$" + "{" + n + ":+:$" + n + "}";
          nuVar = ''" + ($env.${n}? | default "") + "'';
          nuConditional = ''" + (if (($env.${n}? | default "") | is-empty) { "" } else { ":" }) + "'';
          toNuAssignment =
            value:
            if lib.typeOf value == "string" then
              let
                withHomeVars =
                  builtins.replaceStrings [ "$HOME" "$USER" ] [ config.home.homeDirectory config.home.username ]
                    value;
                # Home Manager session variables use shell syntax. Translate
                # self-references such as $TERMINFO_DIRS${TERMINFO_DIRS:+:}
                # before Nushell sees the value as a literal string.
                expanded = builtins.replaceStrings [ shellVar ] [ nuVar ] (
                  builtins.replaceStrings
                    [ shellConditional shellConditionalWithValue ]
                    [ nuConditional nuConditional ]
                    withHomeVars
                );
              in
              "$env.${n} = \"${expanded}\""
            else
              "$env.${n} = ${toString value}";
        in
        lib.pipe v [ toNuAssignment ]
      ) vars
    );
in
{
  programs.nushell.extraEnv = lib.mkBefore ''
    ${exportToNuEnv config.home.sessionVariables}
  '';
}
