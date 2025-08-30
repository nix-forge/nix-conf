profileName:
{ pkgs, inputs, ... }:
let
  extensions = pkgs.callPackage ./marketplace.nix { inherit inputs; };
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.extraCompatible; [
      ## Copilot
      github.copilot
      github.copilot-chat

      ## Codex
      openai.chatgpt
    ];
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
