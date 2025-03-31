{ lib, pkgs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      xuanli.spice
    ];

  programs.vscode.userSettings = {
    "files.associations" = {
      "*.spice" = "spice";
      "*.sp" = "spice";
    };
  };
}
