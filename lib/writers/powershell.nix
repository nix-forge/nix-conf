{ lib, ... }: {
  writePowerShell =
    {
      pkgs,
      excludeRules ? [ ],
      compatibilityVersions ? [ "5.1" ],
    }:
    name: text:
    let
      analyzer = pkgs.callPackage ../../pkgs/pkgs/by-name/ps/psscriptanalyzer/package.nix { };
      settings = (pkgs.formats.json { }).generate "powershell-analysis-settings.json" {
        IncludeDefaultRules = true;
        ExcludeRules = excludeRules;
        Rules.PSUseCompatibleSyntax = {
          Enable = true;
          TargetVersions = compatibilityVersions;
        };
      };
    in
    pkgs.writeTextFile {
      inherit name text;
      checkPhase = (import ../templates/text.nix) ./scripts/check-powershell-source.sh {
        lib_getExe_pkgs_powershell = lib.getExe pkgs.powershell;
        check_powershell_ps1 = ./check-powershell.ps1;
        analyzer_modulePath = analyzer.modulePath;
        inherit settings;
      };
    };
}
