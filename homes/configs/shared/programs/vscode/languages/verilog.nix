{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      #
      mshr-h.veriloghdl
    ];

  programs.vscode.userSettings = { };
}
