profileName:
{ pkgs, lib, ... }@args:
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
      astral-sh.ty
      ms-python.mypy-type-checker

      kevinrose.vsc-python-indent

      ms-toolsai.jupyter-renderers
      ms-toolsai.jupyter
      google.colab

      njpwerner.autodocstring
      rodolphebarbanneau.python-docstring-highlighter
    ];

    userSettings = {
      "[python]" = {
        "editor.tabSize" = 4;
        "editor.defaultFormatter" = "charliermarsh.ruff";
      };

      "ruff.path" = [ (lib.getExe pkgs.ruff) ];
      "ruff.lint.ignore" = [
        "ERA001"
        "W293"
        "F841"
        "E303"
      ];
      "errorLens.excludeBySource" = [ "Ruff" ];

      "python.analysis.autoImportCompletions" = false;
      "python.analysis.typeCheckingMode" = "standard";

      "python.terminal.activateEnvironment" = false;

      # TODO: find a way to highlight docstrings with ty when pylance is disabled
      "python.languageServer" = "None"; # using ty instead
    };
  };
}
