{ lib, pkgs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      ms-azuretools.vscode-docker
    ];

  programs.vscode.profiles.default.userSettings = { };
}
