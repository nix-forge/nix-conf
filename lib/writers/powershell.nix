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
      checkPhase =
        ((import ./bash.nix { inherit (pkgs) lib; }).renderBashText { inherit pkgs; })
          {
            name = "check-powershell-source.sh";
            text = ''
              # shellcheck shell=bash
              # Nix builder/activation callers and rendered fragments provide external variables.
              # shellcheck disable=SC2154
              export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache" XDG_CONFIG_HOME="$TMPDIR/config"
              export DOTNET_CLI_HOME="$TMPDIR/dotnet" POWERSHELL_TELEMETRY_OPTOUT=1
              mkdir -p "$HOME"
              @lib_getExe_pkgs_powershell@ -NoLogo -NoProfile -NonInteractive \
                -File @check_powershell_ps1@ -Path "$target" \
                -Analyzer @analyzer_modulePath@/PSScriptAnalyzer.psd1 -Settings @settings@
            '';
          }
          {
            lib_getExe_pkgs_powershell = lib.getExe pkgs.powershell;
            check_powershell_ps1 = ./check-powershell.ps1;
            analyzer_modulePath = analyzer.modulePath;
            inherit settings;
          };
    };
}
