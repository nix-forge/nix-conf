{ pkgs, inputs, ... }:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [ "jeff-hykin.better-cpp-syntax" ]
    # ++ (with pkgs.vscode-extensions; [ ms-vscode.cpptools ])
    ;

    userSettings = {
      "[c]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "ms-vscode.cpptools";
      };

      "[cpp]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "ms-vscode.cpptools";
      };

      "C_Cpp.default.includePath" = [ "\${workspaceFolder}/**" ];

      "C_Cpp.default.compilerPath" = if pkgs.stdenv.hostPlatform.isDarwin then "clang++" else "g++";
      "C_Cpp.default.cStandard" = "c23";
      "C_Cpp.default.cppStandard" = "c++23";
      "C_Cpp.default.intelliSenseMode" =
        if pkgs.stdenv.hostPlatform.isAarch64 then
          if pkgs.stdenv.hostPlatform.isDarwin then "macos-clang-arm64" else "linux-gcc-arm64"
        else if pkgs.stdenv.hostPlatform.isDarwin then
          "macos-clang-x64"
        else
          "linux-gcc-x64";
      "C_Cpp.intelliSenseEngineFallback" = "enabled";
      "C_Cpp.codeAnalysis.clangTidy.enabled" = true;
    };
  };
}
