{ pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferReleases;
    [
      ms-python.python
      ms-python.vscode-pylance
      ms-python.debugpy

      kevinrose.vsc-python-indent

      ms-toolsai.jupyter-renderers
      ms-toolsai.jupyter
    ];

  programs.vscode.userSettings = {
    "[python]" = {
      "editor.tabSize" = 4;
      "editor.defaultFormatter" = "ms-python.black-formatter";
    };

    "python.analysis.autoImportCompletions" = true;
    "python.analysis.typeCheckingMode" = "standard";
  };
}
