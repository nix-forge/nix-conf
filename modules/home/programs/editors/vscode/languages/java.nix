profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      redhat.java
      vscjava.vscode-java-debug
      vscjava.vscode-java-test
      vscjava.vscode-maven
      vscjava.vscode-java-dependency

      shengchen.vscode-checkstyle
    ];

    userSettings = {
      "[java]" = {
        "editor.defaultFormatter" = "redhat.java";
        "editor.tabSize" = 4;
      };

      "java.configuration.updateBuildConfiguration" = "automatic";
      "java.import.gradle.enabled" = true;
      "java.import.maven.enabled" = true;

      "java.referencesCodeLens.enabled" = true;
      "java.implementationsCodeLens.enabled" = true;
      "java.completion.guessMethodArguments" = "auto";

      "java.jdt.ls.java.home" = "${pkgs.temurin-bin}";

      "java.configuration.runtimes" = [
        # Latest JDK
        {
          name = "JavaSE-${lib.versions.major pkgs.temurin-bin.version}";
          path = "${pkgs.temurin-bin}";
          default = true;
        }
        # JDK 8
        {
          name = "JavaSE-1.8";
          path = "${pkgs.jdk8}";
        }
      ];
    };
  };
}
