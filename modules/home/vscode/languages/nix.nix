{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "jnoortheen.nix-ide"
      "ionutvmi.path-autocomplete"
    ];

    userSettings = {
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = lib.getExe pkgs.nixd;
      "nix.serverSettings".nixd = {
        formatting.command = [
          "${lib.getExe pkgs.nixfmt}"
          "--filename={file}"
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
