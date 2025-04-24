{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  programs.vscode.profiles.default.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { inherit inputs; };
    in
    with extensions.preferNixpkgsThenPreRelease;
    [
      llvm-vs-code-extensions.vscode-clangd
      ms-vscode.cmake-tools
      vadimcn.vscode-lldb
      pierre-payen.gdb-syntax
    ];

  programs.vscode.profiles.default.userSettings = {
    "[c]" = {
      "editor.tabSize" = 2;
      "editor.defaultFormatter" = "llvm-vs-code-extensions.vscode-clangd";
    };

    "[cpp]" = {
      "editor.tabSize" = 2;
      "editor.defaultFormatter" = "llvm-vs-code-extensions.vscode-clangd";
    };

    "cmake.showOptionsMovedNotification" = false;
    "cmake.cmakePath" = lib.getExe pkgs.cmake;
    "C_Cpp.intelliSenseEngine" = "disabled"; # IntelliSense from Microsoft conflicts with clangd
    "clangd.path" = lib.getExe' pkgs.clang-tools "clangd";
  };
}
