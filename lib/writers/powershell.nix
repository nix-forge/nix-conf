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
      checkPhase = ''
        export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache" XDG_CONFIG_HOME="$TMPDIR/config"
        export DOTNET_CLI_HOME="$TMPDIR/dotnet" POWERSHELL_TELEMETRY_OPTOUT=1
        mkdir -p "$HOME"
        ${lib.getExe pkgs.powershell} -NoLogo -NoProfile -NonInteractive \
          -File ${./check-powershell.ps1} -Path "$target" \
          -Analyzer ${analyzer.modulePath}/PSScriptAnalyzer.psd1 -Settings ${settings}
      '';
    };
}
