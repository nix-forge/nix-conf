{ lib, config, ... }:
let
  inherit (lib.hm.nushell) toNushell;
  inherit (config.home) homeDirectory username;
  renderNuEnvironment =
    vars:
    lib.concatMapAttrsStringSep "\n" (
      name: value:
      let
        current = ''($env.${name}? | default "")'';
        conditional = suffix: ''(if (${current} | is-empty) { "" } else { ${suffix} })'';
        substitutions = {
          ${"$" + name} = current;
          "\${${name}}" = current;
          "\${${name}:+:}" = conditional ''":"'';
          ${"$" + "{" + name + ":+:$" + name + "}"} = conditional ''":" + ${current}'';
        };
        pattern = "(${lib.concatMapStringsSep "|" lib.escapeRegex (builtins.attrNames substitutions)})";
        expanded = builtins.replaceStrings [ "$HOME" "$USER" ] [ homeDirectory username ] value;
        # Serialize literal pieces separately from the supported shell-style
        # self references. Quotes, backslashes, and newlines stay data.
        expression = lib.concatMapStringsSep " + " (
          part: if builtins.isList part then substitutions.${builtins.head part} else toNushell { } part
        ) (builtins.split pattern expanded);
      in
      assert builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null;
      "$env.${name} = ${if builtins.isString value then expression else toNushell { } value}"
    ) vars;
in
{
  programs.nushell.extraEnv = lib.mkBefore (renderNuEnvironment config.home.sessionVariables);
}
