profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.release; [
      ms-mssql.mssql
      mtxr.sqltools
    ];

    userSettings = { };
  };
}
