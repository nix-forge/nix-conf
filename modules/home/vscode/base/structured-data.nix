{
  config,
  lib,
  pkgs,
  ...
}:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [
      "github.vscode-github-actions"
      "redhat.vscode-yaml"
      "tamasfe.even-better-toml"
      "mechatroner.rainbow-csv"
      "nefrob.vscode-just-syntax"
    ];
    userSettings = {
      "[yaml]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "redhat.vscode-yaml";
      };
      "yaml.format.printWidth" = 80;
      "yaml.format.proseWrap" = "always";
      "yaml.disableSchemaDetection" = [
        "**/.github/workflows/*.yml"
        "**/.github/workflows/*.yaml"
      ];
      "[json]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "vscode.json-language-features";
      };
      "[jsonc]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "vscode.json-language-features";
      };
      "[github-actions-workflow]" = {
        "editor.defaultFormatter" = "redhat.vscode-yaml";
      };
      "[toml]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "tamasfe.even-better-toml";
      };
      "evenBetterToml.formatter.allowedBlankLines" = 2;
      "evenBetterToml.formatter.columnWidth" = 80;
      "evenBetterToml.taplo.bundled" = false;
      "evenBetterToml.taplo.path" = lib.getExe pkgs.taplo;
      "[just]"."editor.defaultFormatter" = "nefrob.vscode-just-syntax";
      "vscode-just.justPath" = lib.getExe pkgs.just;
      "vscode-just.lspPath" = lib.getExe pkgs.just-lsp;
      "markdown.validate.enabled" = true;

      "[markdown]" = {
        "editor.wordWrap" = "on";
        "files.trimTrailingWhitespace" = false;
      };
    };
  };
}
