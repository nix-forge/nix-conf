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
      "mgmcdermott.vscode-language-babel"
    ];

    userSettings = {
      # Opt in per repository; existing ESLint projects retain their tooling.
      "oxc.requireConfig" = true;
      "oxc.path.oxlint" = lib.getExe pkgs.oxlint;
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
