{ config, pkgs, ... }:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [
      "redhat.java"
      "vscjava.vscode-java-debug"
      "vscjava.vscode-java-test"
      "vscjava.vscode-maven"
      "vscjava.vscode-java-dependency"

    ];

    userSettings = {
      "[java]" = {
        "editor.defaultFormatter" = "redhat.java";
        "editor.tabSize" = 4;
      };

      "java.configuration.updateBuildConfiguration" = "interactive";
      "java.import.gradle.enabled" = true;
      "java.import.maven.enabled" = true;

      "java.referencesCodeLens.enabled" = true;
      "java.implementationCodeLens" = "types";
      "java.completion.guessMethodArguments" = "auto";

      "java.jdt.ls.java.home" = "${pkgs.temurin-bin-25}";

      # The tooling JDK runs JDT LS. Project build files/dev shells select
      # target runtimes; do not install unrelated legacy JDKs globally.
    };
  };
}
