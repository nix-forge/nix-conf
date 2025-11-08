profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      ms-python.python
      ms-python.vscode-pylance
      ms-python.debugpy

      charliermarsh.ruff

      kevinrose.vsc-python-indent

      ms-toolsai.jupyter-renderers
      ms-toolsai.jupyter

      njpwerner.autodocstring
      rodolphebarbanneau.python-docstring-highlighter
    ];

    userSettings = {
      "[python]" = {
        "editor.tabSize" = 4;
        "editor.defaultFormatter" = "charliermarsh.ruff";
      };

      "python.analysis.autoImportCompletions" = true;
      "python.analysis.typeCheckingMode" = "standard";

      "python.terminal.activateEnvironment" = false;
    };
  };
}
