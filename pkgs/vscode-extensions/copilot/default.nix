{ lib, vscode-utils }:
vscode-utils.buildVscodeMarketplaceExtension {
  mktplcRef = {
    publisher = "github";
    name = "copilot";
    version = "1.373.1788";
    hash = "sha256-l12UNAF5Nk8hyzLw/AL08I6mAF/fJDHa0mvvD99StbE=";
  };

  meta = {
    description = "GitHub Copilot uses OpenAI Codex to suggest code and entire functions in real-time right from your editor";
    downloadPage = "https://marketplace.visualstudio.com/items?itemName=GitHub.copilot";
    homepage = "https://github.com/features/copilot";
    license = lib.licenses.unfree;
  };
}
