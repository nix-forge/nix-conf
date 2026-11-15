{ ... }: {
  imports = [
    ../default.nix
    ../base/javascript-tools.nix
  ];
  programs.vscode.profiles.default.userSettings = {
    "[javascript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
    };
    "[javascriptreact]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.tabSize" = 2;
    };
  };
}
