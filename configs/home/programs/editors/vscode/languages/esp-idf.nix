{ lib, pkgs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      espressif.esp-idf-extension
    ];

  programs.vscode.profiles.default.userSettings = {};
}
