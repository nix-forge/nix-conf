{ config, ... }:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [
    ../default.nix
    ../base/javascript-tools.nix
  ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [ "bradlc.vscode-tailwindcss" ];
    userSettings = {
      "[html]"."editor.defaultFormatter" = "vscode.html-language-features";
      "[css]"."editor.defaultFormatter" = "vscode.css-language-features";
      "[scss]"."editor.defaultFormatter" = "vscode.css-language-features";
      "[less]"."editor.defaultFormatter" = "vscode.css-language-features";
    };
  };
}
