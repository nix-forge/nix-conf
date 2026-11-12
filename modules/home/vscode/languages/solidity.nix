{ config, ... }:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [ "nomicfoundation.hardhat-solidity" ];

    userSettings = {
      "[solidity]"."editor.defaultFormatter" = "NomicFoundation.hardhat-solidity";
      "solidity.telemetry" = false;
    };
  };
}
