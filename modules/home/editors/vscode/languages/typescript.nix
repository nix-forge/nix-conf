profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.release; [
      dbaeumer.vscode-eslint
      esbenp.prettier-vscode
      idered.npm
      christian-kohler.npm-intellisense
      christian-kohler.path-intellisense
      pmneo.tsimporter
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
