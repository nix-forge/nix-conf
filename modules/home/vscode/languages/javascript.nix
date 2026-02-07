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
      "mgmcdermott.vscode-language-babel"
    ];

    userSettings = {
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
  };
}
