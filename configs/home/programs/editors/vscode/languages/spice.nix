{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      chillibits.spicelang
    ];

  programs.vscode.userSettings = {
  };
}
