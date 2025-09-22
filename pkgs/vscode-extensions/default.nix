{ callPackage, writeShellApplication, curl, jq, gnused, coreutils, nix, python3, ... }:
let
  updateScriptPackage = writeShellApplication {
    name = "update-vscode-extensions";
    runtimeInputs = [ curl jq gnused coreutils nix python3 ];
    text = builtins.readFile ./update.sh;
  };
in
{
  copilot = callPackage ./copilot { };
  copilot-chat = callPackage ./copilot-chat { };

  # Expose the updater via this attrset for convenience
  updateScript = {
    command = [ "${updateScriptPackage}/bin/update-vscode-extensions" ];
  };
  updateScriptPackage = updateScriptPackage;
}
