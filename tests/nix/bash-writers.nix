{ pkgs, myLib }:
let
  inherit (pkgs) lib;
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  expected = "quotes: '\" dollar: $HOME backslash: \\";
  template = pkgs.writeText "writer.sh.in" (builtins.readFile ./scripts/bash-argument-probe.sh.in);
  scriptFor =
    dir:
    writeBashTemplate {
      name = "writer-probe";
      src = template;
      inherit dir;
      replacements = {
        bash = lib.getExe pkgs.bash;
        value = lib.escapeShellArg expected;
      };
    };
  bin = scriptFor "bin";
  single = scriptFor null;
  libexec = scriptFor "libexec";
  bodyFor =
    body:
    writeBashTemplate {
      name = "body-probe";
      dir = "bin";
      src = ./scripts/body-probe.sh.in;
      replacements = {
        bash = lib.getExe pkgs.bash;
        inherit body;
      };
    };
  relaxed = bodyFor (builtins.readFile ./scripts/body-relaxed.sh);
  parseOnly = bodyFor (builtins.readFile ./scripts/body-parse-only.sh);
  pathReplacementSource = ./bash-writers.nix;
  pathReplacement = writeBashTemplate {
    name = "path-replacement-probe";
    dir = "bin";
    src = pkgs.writeText "path-replacement.sh.in" (
      builtins.readFile ./scripts/path-replacement-probe.sh.in
    );
    replacements = {
      bash = lib.getExe pkgs.bash;
      source = pathReplacementSource;
    };
  };
  isolatedRuntime = writeBashTemplate {
    name = "isolated-runtime-probe";
    dir = "bin";
    src = pkgs.writeText "isolated-runtime.sh.in" (
      builtins.readFile ./scripts/isolated-runtime-probe.sh.in
    );
    replacements = {
      bash = lib.getExe pkgs.bash;
      hello = lib.escapeShellArg (lib.getExe pkgs.hello);
      runtimePath = lib.escapeShellArg (lib.makeBinPath [ pkgs.hello ]);
    };
    runtimeInputs = [ pkgs.hello ];
    inheritPath = false;
  };
  alias = writeBashTemplate {
    name = "alias-probe";
    src = pkgs.writeText "alias-body.sh" (builtins.readFile ./scripts/invoked-name-probe.sh);
    replacements = { };
  };
in
{
  bash-template-writer =
    assert bin.meta.mainProgram == "writer-probe";
    assert libexec.meta.mainProgram == "writer-probe";
    pkgs.runCommand "bash-template-writer" { inherit expected; } (
      (import ../../lib/templates/text.nix) ./scripts/bash-template-writer.sh {
        lib_getExe_bin = lib.getExe bin;
        inherit single;
        inherit libexec;
        lib_getExe_pkgs_bashNonInteractive = lib.getExe pkgs.bashNonInteractive;
        lib_getExe_relaxed = lib.getExe relaxed;
        lib_getExe_parseOnly = lib.getExe parseOnly;
        lib_getExe_pathReplacement = lib.getExe pathReplacement;
        lib_getExe_isolatedRuntime = lib.getExe isolatedRuntime;
        inherit alias;
      }
    );
  bash-template-invalid-syntax = pkgs.testers.testBuildFailure' {
    drv = bodyFor "if then";
    expectedBuilderExitCode = 2;
    expectedBuilderLogEntries = [ "syntax error" ];
  };
  bash-template-invalid-lint = pkgs.testers.testBuildFailure' {
    drv = bodyFor "printf '%s\\n' $1";
    expectedBuilderLogEntries = [ "SC2086" ];
  };
}
