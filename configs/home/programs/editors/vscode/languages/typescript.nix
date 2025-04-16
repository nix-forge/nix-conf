{ lib, pkgs, inputs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      dbaeumer.vscode-eslint
      esbenp.prettier-vscode
      idered.npm
      christian-kohler.npm-intellisense
      christian-kohler.path-intellisense
      redhat.vscode-yaml
      pmneo.tsimporter
    ];

  programs.vscode.profiles.default.userSettings = {
    "typescript.suggest.paths" = false;
    "[typescript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
      "prettier.tabWidth" = 2;
    };
    "[typescriptreact]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
      "prettier.tabWidth" = 2;
    };
  };
}
