{ lib, vscode-utils }:
vscode-utils.buildVscodeMarketplaceExtension {
  mktplcRef = {
    publisher = "github";
    name = "copilot-chat";
    version = "0.32.2025092201";
    hash = "sha256-Ui6cFNuOXf5HLnWSZGOK1uY8a9m0KqpD1XRsQCg45UA=";
  };

  meta = {
    description = "GitHub Copilot Chat is a companion extension to GitHub Copilot that houses experimental chat features";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat";
    homepage = "https://github.com/features/copilot";
    license = lib.licenses.mit;
  };
}
