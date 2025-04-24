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
      eww-yuck.yuck
      kress95.vscode-parinfer-kress95
    ];

  # programs.vscode.profiles.default.userSettings = {
  #   "[css]" = {
  #     "editor.defaultFormatter" = "aeschli.vscode-css-formatter";
  #   };
  # };
}
