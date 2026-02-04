profileName:
{
  pkgs,
  self,
  system,
  ...
}@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = [
      self.packages.${system}.vscode-extensions-copilot
      self.packages.${system}.vscode-extensions-copilot-chat
    ]
    ++ (with extensions.release; [
      ## Codex
      openai.chatgpt
    ]);

    userSettings = {
      ## Copilot
      # Base
      "chat.agent.maxRequests" = 50;
      "chat.agent.enabled" = true;
      "github.copilot.nextEditSuggestions.enabled" = false; # this is annoying
      "chat.viewSessions.orientation" = "stacked";

      # Preview
      "github.copilot.chat.codesearch.enabled" = true;

      # Experimental
      "github.copilot.chat.anthropic.tools.websearch.enabled" = true;
      "github.copilot.chat.anthropic.tools.websearch.maxUses" = 20;
      "github.copilot.chat.anthropic.thinking.budgetTokens" = 32000;
      "inlineChat.notebookAgent" = true;
      "github.copilot.chat.notebook.enhancedNextEditSuggestions.enabled" = true;
      "github.copilot.chat.notebook.followCellExecution.enabled" = true;

      ## Gemini
      "http.systemCertificatesNode" = true;
      "geminicodeassist.project" = "splendid-skill-485101-j7";
      "geminicodeassist.enableTelemetry" = false;
      "geminicodeassist.displayInlineContextHint" = false;
    };
  };
}
