{ ... }: {
  imports = [
    ../default.nix
    ../base/javascript-tools.nix
  ];
  programs.vscode.profiles.default.userSettings = {
    "[typescript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
    };
    "[typescriptreact]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
    };
  };
}
