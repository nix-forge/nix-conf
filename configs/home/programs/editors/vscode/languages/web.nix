profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      aeschli.vscode-css-formatter

      bradlc.vscode-tailwindcss
      esbenp.prettier-vscode
    ];

    userSettings = {
      "[css]" = {
        "editor.defaultFormatter" = "aeschli.vscode-css-formatter";
      };
    };
  };
}
