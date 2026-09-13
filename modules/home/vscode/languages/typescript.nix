{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "dbaeumer.vscode-eslint"
      "esbenp.prettier-vscode"
      "oxc.oxc-vscode"
      "idered.npm"
      "christian-kohler.npm-intellisense"
      "christian-kohler.path-intellisense"
      "pmneo.tsimporter"
    ];

    userSettings = {
      "oxc.requireConfig" = true;
      "oxc.path.oxlint" = lib.getExe pkgs.oxlint;
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
  };
}
