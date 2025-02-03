{ lib, pkgs, ... }:
let
  dictionary = import ./dictionaries/nix.nix;
in
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      jnoortheen.nix-ide
      ionutvmi.path-autocomplete
    ];

  programs.vscode.userSettings = {
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = lib.getExe pkgs.nixd;
    "nix.serverSettings".nixd = {
      formatting.command = [
        "${lib.getExe pkgs.nixfmt-rfc-style}"
        "-q"
        "-"
      ];
    };
    "[nix]" = {
      # appears to be buggy at the moment
      "editor.stickyScroll.enabled" = false;
      # allow paths to be auto-completed
      "path-autocomplete.triggerOutsideStrings" = true;
      # don't add a trailing slash for dirs
      "path-autocomplete.enableFolderTrailingSlash" = false;
      # unset default formatter
      "editor.defaultFormatter" = "";
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
