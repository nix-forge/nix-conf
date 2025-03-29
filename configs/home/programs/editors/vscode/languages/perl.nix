{ lib, pkgs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      #
      fractalboy.pls
    ];

  programs.vscode.profiles.default.userSettings = {
    "pls.cmd" = lib.getExe pkgs.perlPackages.PLS;
  };
}
