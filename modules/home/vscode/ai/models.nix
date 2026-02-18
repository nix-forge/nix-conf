{ pkgs, inputs, ... }:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      ## Copilot
      "github.copilot-chat"

      ## Codex
      "openai.chatgpt"
    ];

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
    };
  };
}
