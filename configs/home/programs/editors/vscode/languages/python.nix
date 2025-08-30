profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
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

    userSettings = {
      "[python]" = {
        "editor.tabSize" = 4;
        "editor.defaultFormatter" = "ms-python.black-formatter";
      };

      # set the location of the black formatter
      "black-formatter.path" = [ "${lib.getExe pkgs.black}" ];

      "python.analysis.autoImportCompletions" = true;
      "python.analysis.typeCheckingMode" = "standard";
    };
  };
}
