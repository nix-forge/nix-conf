profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [ xuanli.spice ];

    userSettings = {
      "files.associations" = {
        "*.spice" = "spice";
        "*.sp" = "spice";
      };
    };
  };
}
