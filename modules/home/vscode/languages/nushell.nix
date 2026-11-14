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
    extensions = catalogExtensions [ "thenuprojectcontributors.vscode-nushell-lang" ];
    userSettings."nushellLanguageServer.nushellExecutablePath" = lib.getExe pkgs.nushell;
  };
}
