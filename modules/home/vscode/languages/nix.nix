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
    extensions = catalogExtensions [
      "jnoortheen.nix-ide"
      "ionutvmi.path-autocomplete"
    ];

    userSettings = {
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = lib.getExe pkgs.nixd;
      "nix.serverSettings".nixd = {
        formatting.command = [
          "${lib.getExe pkgs.nixfmt}"
          "--width=100"
          "--indent=2"
          "--strict"
        ];
      };

      "[nix]" = {
        "editor.stickyScroll.enabled" = false;
        "path-autocomplete.triggerOutsideStrings" = true;
        "path-autocomplete.enableFolderTrailingSlash" = false;
        "editor.defaultFormatter" = "jnoortheen.nix-ide";
        "editor.formatOnType" = false;
      };
    };
  };
}
