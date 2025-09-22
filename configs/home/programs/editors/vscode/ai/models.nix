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
