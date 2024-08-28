{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      aeschli.vscode-css-formatter

      bradlc.vscode-tailwindcss
      esbenp.prettier-vscode
    ];

  programs.vscode.userSettings = {
    "[css]" = {
      "editor.defaultFormatter" = "aeschli.vscode-css-formatter";
    };
  };
}
