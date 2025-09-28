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
      exec python3 ${../update.py} "$@"
    '';
  };
in
vscode-utils.buildVscodeMarketplaceExtension rec {
  mktplcRef = {
    publisher = "github";
    name = "copilot-chat";
    version = "0.31.3";
    hash = "sha256-Kvg5gmvAcz+K6mWBzWoNnkqEWAPRgC+w0idUC6RzM0g=";
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
