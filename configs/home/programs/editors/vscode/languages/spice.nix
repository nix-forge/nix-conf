{ lib, pkgs, inputs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      xuanli.spice
    ];

  programs.vscode.profiles.default.userSettings = {
    "files.associations" = {
      "*.spice" = "spice";
      "*.sp" = "spice";
    };
  };
}
