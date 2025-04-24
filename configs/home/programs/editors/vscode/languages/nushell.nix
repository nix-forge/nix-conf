{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  home.packages = [ pkgs.nushell ];

  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      #
      thenuprojectcontributors.vscode-nushell-lang
    ];
}
