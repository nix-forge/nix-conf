{ pkgs, lib, ... }: {
  reason = "The selected Nixpkgs Darwin GUI runs under shared Electron identity. Use the same official release's intact Developer ID signed vendor app for native identity/consent, without changing the official CLI or persistent backend. Native migration and connection acceptance remain separate.";
  upstream = "https://github.com/pingdotgg/t3code/releases/tag/v0.1.8";
  removal = "The selected official Nixpkgs Darwin package ships the signed vendor GUI and passes signature, provider, encrypted-catalog/Keychain continuity and native connection checks without this integration; retire this fix, extraction helper and regression together.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0.1.8";
    until = "0.1.9";
  };
  apply =
    package:
    if package.version != "0.1.8" then
      throw "Review the signed T3 vendor release before updating"
    else if !(package ? unwrapped && package ? resourceMonitor && package ? override) then
      throw "Expected official T3 package/override/provider wrapper contract"
    else
      let
        appName = "T3 Code (Beta)";
        archive = pkgs.fetchurl {
          url = "https://github.com/pingdotgg/t3code/releases/download/v0.1.8/T3-Code-0.1.8-arm64.zip";
          hash = "sha256-g5Kk9Zyi13LEQIcfw8/yn7Sv0TT8UhBkiocq0I7MITY=";
        };
        vendorApp = pkgs.stdenvNoCC.mkDerivation {
          pname = "t3code-darwin-vendor-app";
          inherit (package) version;
          src = archive;
          strictDeps = true;
          nativeBuildInputs = [ pkgs.unzip ];
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          dontFixup = true;
          dontStrip = true;
          installPhase = (''
            # shellcheck shell=bash
            # Standard Nix derivation variables supply the reviewed fixed-output archive.
            # shellcheck disable=SC2154
            set -euo pipefail
            unzip -q "$src" -d vendor
            test -d "vendor/T3 Code (Beta).app"
            mkdir -p "$out/Applications"
            cp -a "vendor/T3 Code (Beta).app" "$out/Applications/"
            # Compare all file bytes and raw symlink targets, not just the main executable.
            diff -qr --no-dereference "vendor/T3 Code (Beta).app" "$out/Applications/T3 Code (Beta).app"
          '');
          meta = package.meta // {
            mainDarwinApp = "${appName}.app";
            platforms = [ "aarch64-darwin" ];
          };
        };
        guiEntry =
          pkgs.runCommand "t3code-vendor-gui-entry"
            {
              inherit (package) version meta;
              passthru = { };
            }
            ''
              mkdir -p "$out/bin"
              ln -s ${lib.escapeShellArg "${vendorApp}/Applications/${appName}.app/Contents/MacOS/${appName}"} "$out/bin/t3code-desktop"
            '';
        # Reuse the official provider-wrapper factory/options, not a second list
        # of provider dependencies. Keep the already selected monitor unchanged.
        guiWrapped = package.override {
          t3code-unwrapped = guiEntry;
          t3code-resource-monitor = package.resourceMonitor;
        };
      in
      pkgs.symlinkJoin {
        inherit (package) pname version;
        meta = package.meta // {
          mainDarwinApp = "${appName}.app";
        };
        paths = [ package ];
        strictDeps = true;
        __structuredAttrs = true;
        passthru = package.passthru // {
          serverPackage = package.serverPackage or package;
          vendorGui = vendorApp;
        };
        postBuild = ''
          # Only this new output's directory links change. No vendor bundle file
          # is rewritten, wrapped, stripped, chmodded or re-signed here.
          rm -rf "$out/Applications"
          mkdir -p "$out/Applications"
          ln -s ${lib.escapeShellArg "${vendorApp}/Applications/${appName}.app"} "$out/Applications/${appName}.app"
          rm "$out/bin/t3code-desktop"
          ln -s ${guiWrapped}/bin/t3code-desktop "$out/bin/t3code-desktop"
        '';
      };
}
