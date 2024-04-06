{ lib, pkgs, ... }: {
  programs.vscode.extensions =
    #
    with pkgs.vscode-marketplace;
    with pkgs.vscode-marketplace-release; [

      ms-python.python
      ms-python.vscode-pylance
      ms-toolsai.jupyter

      njpwerner.autodocstring
      kevinrose.vsc-python-indent

      ms-python.black-formatter
      ms-python.autopep8
      eeyore.yapf
    ];

  programs.vscode.userSettings = {
    "[python]" = {
      "editor.tabSize" = 4;
      "editor.defaultFormatter" = "ms-python.black-formatter";
    };

    "python.analysis.autoImportCompletions" = true;
    "python.analysis.typeCheckingMode" = "basic";
  };
}
