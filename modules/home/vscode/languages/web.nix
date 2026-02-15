{ pkgs, inputs, ... }:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [
      "aeschli.vscode-css-formatter"

      "bradlc.vscode-tailwindcss"
      "esbenp.prettier-vscode"
    ];

    userSettings = {
      "[css]" = {
        "editor.defaultFormatter" = "aeschli.vscode-css-formatter";
      };
    };
  };
}
