{ lib, pkgs, inputs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      aeschli.vscode-css-formatter

      bradlc.vscode-tailwindcss
      esbenp.prettier-vscode
    ];

  programs.vscode.profiles.default.userSettings = {
    "[css]" = {
      "editor.defaultFormatter" = "aeschli.vscode-css-formatter";
    };
  };
}
