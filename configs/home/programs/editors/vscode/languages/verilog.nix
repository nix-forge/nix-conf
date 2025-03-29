{ lib, pkgs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      #
      mshr-h.veriloghdl
    ];

  programs.vscode.profiles.default.userSettings = { };
}
