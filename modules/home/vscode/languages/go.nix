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
    extensions = catalogExtensions [ "golang.go" ];
    userSettings = {
      "[go]"."editor.defaultFormatter" = "golang.go";
      "go.alternateTools" = {
        gopls = lib.getExe pkgs.gopls;
        dlv = lib.getExe pkgs.delve;
      };
      "go.toolsManagement.autoUpdate" = false;
      "go.toolsManagement.checkForUpdates" = "off";
      "go.formatTool" = "default";
    };
  };
}
