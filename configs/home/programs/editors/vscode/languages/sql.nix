profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      ms-mssql.mssql
      mtxr.sqltools
    ];

    userSettings = { };
  };
}
