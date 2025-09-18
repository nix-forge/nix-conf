profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      mathworks.language-matlab
      affenwiesel.matlab-formatter
    ];

    userSettings = { };
  };
}
