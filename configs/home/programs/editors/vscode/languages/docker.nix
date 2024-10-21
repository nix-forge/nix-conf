{ lib, pkgs, ... }:
{
  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      ms-azuretools.vscode-docker
    ];

  programs.vscode.userSettings = { };
}
