{ lib, pkgs, inputs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      #
      fractalboy.pls
    ];

  programs.vscode.profiles.default.userSettings = {
    "pls.cmd" = lib.getExe pkgs.perlPackages.PLS;
  };
}
