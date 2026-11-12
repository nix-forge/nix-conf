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
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [
      "jeff-hykin.better-cpp-syntax"
      "ms-vscode.cmake-tools"
      "llvm-vs-code-extensions.vscode-clangd"
    ];

    userSettings = {
      "[c]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "llvm-vs-code-extensions.vscode-clangd";
      };

      "[cpp]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "llvm-vs-code-extensions.vscode-clangd";
      };

      # clangd owns completion, diagnostics and formatting. Compilation flags
      # come from the project's compile_commands.json, not a global compiler.
      "clangd.path" = lib.getExe' pkgs.clang-tools "clangd";
      "clangd.checkUpdates" = false;
      "cmake.configureOnOpen" = false;
    };
  };
}
