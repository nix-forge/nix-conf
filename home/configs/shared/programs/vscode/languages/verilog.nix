{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferReleases;
    [
      #
      mshr-h.veriloghdl
    ];

  programs.vscode.userSettings = { };
}
