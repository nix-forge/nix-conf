{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      dbaeumer.vscode-eslint
      esbenp.prettier-vscode
      idered.npm
      christian-kohler.npm-intellisense
      christian-kohler.path-intellisense
      xabikos.javascriptsnippets
      mgmcdermott.vscode-language-babel
      redhat.vscode-yaml
    ];

  programs.vscode.userSettings = {
    "javascript.suggest.paths" = false;
    "[javascript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
      "prettier.tabWidth" = 2;
    };
    "[javascriptreact]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
      "prettier.tabWidth" = 2;
    };
  };
}
