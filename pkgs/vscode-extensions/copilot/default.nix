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
    name = "copilot";
    version = "1.373.1788";
    hash = "sha256-l12UNAF5Nk8hyzLw/AL08I6mAF/fJDHa0mvvD99StbE=";
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
    description = "GitHub Copilot uses OpenAI Codex to suggest code and entire functions in real-time right from your editor";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=GitHub.copilot";
    homepage = "https://github.com/features/copilot";
    license = lib.licenses.unfree;
  };
}
