{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      mathworks.language-matlab
      affenwiesel.matlab-formatter
    ];

  programs.vscode.profiles.default.userSettings = { };
}
