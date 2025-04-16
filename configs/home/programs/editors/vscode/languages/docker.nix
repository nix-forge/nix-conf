{ lib, pkgs, inputs, ... }:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      ms-azuretools.vscode-docker
    ];

  programs.vscode.profiles.default.userSettings = { };
}
