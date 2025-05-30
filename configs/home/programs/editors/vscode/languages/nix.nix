{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  dictionary = import ./dictionaries/nix.nix;
in
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      jnoortheen.nix-ide
      ionutvmi.path-autocomplete
    ];

  programs.vscode.profiles.default.userSettings = {
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = lib.getExe inputs.nixd.packages.${pkgs.system}.nixd;
    "nix.serverSettings".nixd = {
      formatting.command = [
        "${lib.getExe pkgs.nixfmt-rfc-style}"
        "--filename={file}"
      ];
    };

    "[nix]" = {
      # appears to be buggy at the moment
      "editor.stickyScroll.enabled" = false;
      # allow paths to be auto-completed
      "path-autocomplete.triggerOutsideStrings" = true;
      # don't add a trailing slash for dirs
      "path-autocomplete.enableFolderTrailingSlash" = false;
      # set default formatter
      "editor.defaultFormatter" = "jnoortheen.nix-ide";

      "editor.formatOnType" = false;
    };

    "cSpell.languageSettings" = [
      {
        languageId = "nix";
        dictionaries = [ "nix" ];
      }
    ];

    "cSpell.customDictionaries" = {
      nix = {
        path = (pkgs.writeText "dictionary-nix" (lib.concatStringsSep "\n" dictionary)).outPath;
        description = "Extra words for the Nix language";
        scope = "user";
      };
    };
  };
}
