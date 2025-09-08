profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions =
      (with extensions.preferNixpkgsThenPreRelease; [ jeff-hykin.better-cpp-syntax ])
      ++ (with extensions.nixpkgs-extensions; [ ms-vscode.cpptools ]);

    userSettings = {
      "[c]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "ms-vscode.cpptools";
      };

      "[cpp]" = {
        "editor.tabSize" = 2;
        "editor.defaultFormatter" = "ms-vscode.cpptools";
      };

      "C_Cpp.default.includePath" = [
        "\${workspaceFolder}/**"
        "\${env:PKG_CONFIG_PATH}"
      ]
      ++ lib.optionals (pkgs.stdenv.isDarwin) [
        "${pkgs.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include"
      ]
      ++ lib.optionals (pkgs.stdenv.isLinux) [
        # "${pkgs.libcxx}/include/c++/v1"
        "/usr/include"
        "/usr/local/include"
      ];

      "C_Cpp.default.compilerPath" = lib.getExe pkgs.stdenv.cc;
      "C_Cpp.default.cStandard" = "c23";
      "C_Cpp.default.cppStandard" = "c++23";
      "C_Cpp.default.intelliSenseMode" =
        if pkgs.stdenv.isAarch64 then
          if pkgs.stdenv.isDarwin then "macos-clang-arm64" else "linux-gcc-arm64"
        else if pkgs.stdenv.isDarwin then
          "macos-clang-x64"
        else
          "linux-gcc-x64";
      "C_Cpp.intelliSenseEngineFallback" = "enabled";
      "C_Cpp.codeAnalysis.clangTidy.enabled" = true;
    };
  };
}
