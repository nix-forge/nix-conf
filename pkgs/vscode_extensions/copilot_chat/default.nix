{
  lib,
  vscode-utils,
  writeShellApplication,
  python3,
  openssl,
  gitMinimal,
}:
let
  pythonWithOpenSSL = python3.override { inherit openssl; };
  python = pythonWithOpenSSL.withPackages (ps: with ps; [ requests ]);
  updateScriptDrv = writeShellApplication {
    name = "update-vscode-extensions";
    runtimeInputs = [
      python
      gitMinimal
    ];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
      extensions_root="$repo_root/pkgs/vscode_extensions"

      if [[ ! -d "$extensions_root" ]]; then
        echo "ERROR vscode-extensions.update: Directory not found: $extensions_root" >&2
        exit 1
      fi

      exec env VSCODE_EXTENSIONS_ROOT="$extensions_root" \
        ${lib.getExe python} ${../update.py} "$@"
    '';
  };
in
vscode-utils.buildVscodeMarketplaceExtension rec {
  mktplcRef = {
    publisher = "github";
    name = "copilot-chat";
    version = "0.32.3";
    hash = "sha256-28MkPo1+trRoZzSHrig0C8UPyDl3ynZg4DNgFkN46NM=";
  };

  passthru = {
    updateScript = {
      command = [
        "${updateScriptDrv}/bin/update-vscode-extensions"
        "--identifier"
        "${mktplcRef.publisher}.${mktplcRef.name}"
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
