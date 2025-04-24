{
  lib,
  pkgs,
  inputs,
  ...
}:
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
      mgmcdermott.vscode-language-babel
      redhat.vscode-yaml
    ];

  programs.vscode.profiles.default.userSettings = {
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
