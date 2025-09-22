{
  lib,
  vscode-utils,
  writeShellApplication,
  curl,
  jq,
  gnused,
  coreutils,
  nix,
  python3,
}:
let
  updateScriptDrv = writeShellApplication {
    name = "update-vscode-extensions";
    runtimeInputs = [
      curl
      jq
      gnused
      coreutils
      nix
      python3
    ];
    text = builtins.readFile ../update.sh;
  };
in
vscode-utils.buildVscodeMarketplaceExtension rec {
  mktplcRef = {
    publisher = "github";
    name = "copilot-chat";
    version = "0.32.2025092201";
    hash = "sha256-Ui6cFNuOXf5HLnWSZGOK1uY8a9m0KqpD1XRsQCg45UA=";
  };

  passthru = {
    updateScript = {
      command = [
        "${updateScriptDrv}/bin/update-vscode-extensions"
        "--only"
        "${mktplcRef.publisher}"
        "${mktplcRef.name}"
      ];
    };
    updateScriptPackage = updateScriptDrv;
  };

  meta = {
    description = "GitHub Copilot Chat is a companion extension to GitHub Copilot that houses experimental chat features";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat";
    homepage = "https://github.com/features/copilot";
    license = lib.licenses.mit;
  };
}
