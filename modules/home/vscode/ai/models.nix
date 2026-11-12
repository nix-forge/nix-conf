{ pkgs, ... }: {
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    # Matches the stable Marketplace version at the pinned package revision.
    # This is an explicit source choice, not an automatic source fallback.
    extensions = [ pkgs.vscode-extensions.github.copilot-chat ];

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
      "inlineChat.notebookAgent" = true;
      "github.copilot.chat.notebook.enhancedNextEditSuggestions.enabled" = true;
      "github.copilot.chat.notebook.followCellExecution.enabled" = true;
    };
  };
}
