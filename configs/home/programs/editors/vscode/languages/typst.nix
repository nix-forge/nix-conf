profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [ myriad-dreamin.tinymist ];

    programs.vscode.profiles.default.userSettings = {
      "formatterMode" = "typstyle";
    };
  };
}
