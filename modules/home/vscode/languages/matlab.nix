{ pkgs, inputs, ... }:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "mathworks.language-matlab"
      "affenwiesel.matlab-formatter"
    ];

    userSettings = { };
  };
}
