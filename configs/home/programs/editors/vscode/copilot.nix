{ pkgs, inputs, ... }:
let
  extensions = pkgs.callPackage ./marketplace.nix { inherit inputs; };
in
{
  programs.vscode.profiles.default = {
    extensions = with extensions.extraCompatible; [
      github.copilot
      github.copilot-chat
    ];
    userSettings = {
      "chat.agent.enabled" = true;
      "github.copilot.nextEditSuggestions.enabled" = true;

      # Preview
      "github.copilot.chat.codesearch.enabled" = true;

      # Experimental
      "github.copilot.chat.agent.thinkingTool" = true;
    };
  };
}
