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
        "editor.formatOnSaveMode" = "file";
        "editor.codeActionsOnSave" = {
          "source.fixAll.ruff" = "explicit";
          "source.organizeImports.ruff" = "explicit";
        };
      };

      "notebook.formatOnSave.enabled" = false;
      "notebook.codeActionsOnSave" = {
        "notebook.source.fixAll.ruff" = "explicit";
        "notebook.source.organizeImports.ruff" = "explicit";
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
      "python.languageServer" = "None"; # using ty instead

      "python.terminal.activateEnvironment" = false; # using direnv instead
    };
  };
}
