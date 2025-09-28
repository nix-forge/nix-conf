{
  lib,
  vscode-utils,
  writeShellApplication,
  python3,
  openssl,
}:
let
  pythonWithOpenSSL = python3.override { inherit openssl; };
  python = pythonWithOpenSSL.withPackages (ps: with ps; [ requests ]);
  updateScriptDrv = writeShellApplication {
    name = "update-vscode-extensions";
    runtimeInputs = [ python ];
    text = ''
      exec ${lib.getExe python} ${../update.py} "$@"
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
        "--identifier ${mktplcRef.publisher}.${mktplcRef.name}"
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
