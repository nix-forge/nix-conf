{ pkgs, myLib }:
let
  cssChecker = myLib.desktop.mkGtkCssChecker { inherit pkgs; };
  writePowerShell = myLib.writers.writePowerShell { inherit pkgs; };
in
{
  gtk-css-parser = pkgs.runCommand "gtk-css-parser" { } (
    (import ../../lib/templates/text.nix) ./scripts/gtk-css-parser.sh { inherit cssChecker; }
  );
  powershell-parser = writePowerShell "valid.ps1" ''
    # Successful validation must not execute this script.
    throw 'This program must only be parsed'
  '';
  powershell-checker-lint = myLib.writers.writePowerShell {
    inherit pkgs;
    compatibilityVersions = [ "7.0" ];
  } "check-powershell.ps1" (builtins.readFile ../../lib/writers/check-powershell.ps1);
  powershell-invalid-syntax = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "invalid.ps1" "function Broken {";
    expectedBuilderLogEntries = [ "Missing closing '}'" ];
  };
  powershell-unused-variable = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "unused.ps1" "$unused = 1";
    expectedBuilderLogEntries = [ "PSUseDeclaredVarsMoreThanAssignments" ];
  };
  powershell-empty-catch = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "empty-catch.ps1" "try { throw 'fixture' } catch { }";
    expectedBuilderLogEntries = [ "PSAvoidUsingEmptyCatchBlock" ];
  };
  powershell-guest-compatibility = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "incompatible.ps1" "$null = $true ? 'yes' : 'no'";
    expectedBuilderLogEntries = [ "PSUseCompatibleSyntax" ];
  };
}
