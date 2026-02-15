{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "ms-python.python"
      "ms-python.vscode-pylance"
      "ms-python.debugpy"

      "ms-toolsai.jupyter-renderers"
      "ms-toolsai.jupyter"
      "google.colab"

      "charliermarsh.ruff"
      "astral-sh.ty"

      "kevinrose.vsc-python-indent"
      "njpwerner.autodocstring"
      "rodolphebarbanneau.python-docstring-highlighter"
    ];

    userSettings = {
      "[python]" = {
        "editor.tabSize" = 4;
        "editor.defaultFormatter" = "charliermarsh.ruff";
      };

      "notebook.formatOnSave.enabled" = true;
      "notebook.defaultFormatter" = "charliermarsh.ruff";

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

      "python.languageServer" = "Pylance";
      # "python.languageServer" = "None"; # using ty instead
    };
  };
}
