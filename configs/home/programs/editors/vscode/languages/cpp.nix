profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      llvm-vs-code-extensions.vscode-clangd
      ms-vscode.cmake-tools
      vadimcn.vscode-lldb
      pierre-payen.gdb-syntax
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

      "cmake.cmakePath" = lib.getExe pkgs.cmake;
      "C_Cpp.intelliSenseEngine" = "disabled"; # IntelliSense from Microsoft conflicts with clangd
      "clangd.path" = lib.getExe' pkgs.clang-tools "clangd";
    };
  };
}
