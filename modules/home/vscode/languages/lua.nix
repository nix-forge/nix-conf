{
  config,
  lib,
  pkgs,
  ...
}:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [ "sumneko.lua" ];
    userSettings = {
      "[lua]"."editor.defaultFormatter" = "sumneko.lua";
      "Lua.misc.executablePath" = lib.getExe pkgs.lua-language-server;
    };
  };
}
