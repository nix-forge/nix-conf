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
    [ myriad-dreamin.tinymist ];

  programs.vscode.profiles.default.userSettings = {
    "formatterMode" = "typstyle";
  };
}
