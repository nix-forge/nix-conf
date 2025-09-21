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
      ## Copilot
      self.packages.${system}.copilot
      self.packages.${system}.copilot-chat
    ]
    ++ (with extensions.preferNixpkgsThenPreRelease; [
      ## Codex
      openai.chatgpt
    ]);

    userSettings = {
      ## Copilot
      # Base
      "chat.agent.enabled" = true;
      "github.copilot.nextEditSuggestions.enabled" = false; # this is annoying

      # Preview
      "github.copilot.chat.codesearch.enabled" = true;

      # Experimental
      "github.copilot.chat.agent.thinkingTool" = true;
    };
  };
}
