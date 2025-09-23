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
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      exec python3 ${../update.py} "$@"
    '';
  };
in
vscode-utils.buildVscodeMarketplaceExtension rec {
  mktplcRef = {
    publisher = "github";
    name = "copilot-chat";
    version = "0.31.0";
    hash = "sha256-jMy6mjPUxz3p1dvrveZ/9tyn+KZ6rBLJinZMBUUb9QY=";
  };

  passthru = {
    updateScript = {
      command = [
        "${updateScriptDrv}/bin/update-vscode-extensions"
        "--only"
        "${mktplcRef.publisher}"
        "${mktplcRef.name}"
        "--source"
        "github"
        "--github-repo"
        "microsoft/vscode-copilot-chat"
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
