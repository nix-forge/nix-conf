{ lib, pkgs, ... }:
{
  home.packages = [
    pkgs.rust-analyzer
    pkgs.slint-lsp
  ];

  programs.vscode.extensions =
    let
      extensions = pkgs.callPackage ../marketplace.nix { };
    in
    with extensions.preferNixpkgs;
    [
      llvm-vs-code-extensions.vscode-clangd
      # ms-vscode.cmake-tools
      vadimcn.vscode-lldb
    ];

  programs.vscode.userSettings = {
    "cmake.showOptionsMovedNotification" = false;
    "cmake.cmakePath" = lib.getExe pkgs.cmake;
    "C_Cpp.intelliSenseEngine" = "disabled"; # IntelliSense from Microsoft conflicts with clangd
    "clangd.path" = lib.getExe' pkgs.clang-tools "clangd";
  };
}
