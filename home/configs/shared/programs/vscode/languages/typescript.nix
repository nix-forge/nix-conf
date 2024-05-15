{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferReleases;
    [
      dbaeumer.vscode-eslint
      esbenp.prettier-vscode
      idered.npm
      christian-kohler.npm-intellisense
      christian-kohler.path-intellisense
      redhat.vscode-yaml
      pmneo.tsimporter
    ];

  programs.vscode.userSettings = {
    "typescript.suggest.paths" = false;
    "[typescript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
      "prettier.tabWidth" = 2;
    };
  };
}
