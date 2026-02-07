{ pkgs, inputs, ... }:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "dbaeumer.vscode-eslint"
      "esbenp.prettier-vscode"
      "idered.npm"
      "christian-kohler.npm-intellisense"
      "christian-kohler.path-intellisense"
      "pmneo.tsimporter"
    ];

    userSettings = {
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
