{ pkgs, lib, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      ms-python.python
      ms-python.vscode-pylance
      ms-python.debugpy

      ms-python.black-formatter

      kevinrose.vsc-python-indent

      ms-toolsai.jupyter-renderers
      ms-toolsai.jupyter

      njpwerner.autodocstring
      rodolphebarbanneau.python-docstring-highlighter
    ];

  programs.vscode.profiles.default.userSettings = {
    "[python]" = {
      "editor.tabSize" = 4;
      "editor.defaultFormatter" = "ms-python.black-formatter";
    };

    # set the location of the black formatter
    "black-formatter.path" = [
      "${lib.getExe pkgs.black}"
      "--line-length"
      "120" # increase the line length from 88
    ];

    "python.analysis.autoImportCompletions" = true;
    "python.analysis.typeCheckingMode" = "standard";
  };
}
