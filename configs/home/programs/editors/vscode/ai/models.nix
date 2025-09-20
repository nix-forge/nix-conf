profileName:
{ pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions =
      (with extensions.extraCompatible; [
        ## Copilot (since extensions is integrated with vscode it requires the version to be compatible)
        github.copilot
        # TODO: re-add when updated nix package is available
        # github.copilot-chat
      ])
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
