{ pkgs, lib, ... }: {
  reason = "The selected Nixpkgs Darwin GUI runs under shared Electron identity. Use the same official release's intact Developer ID signed vendor app for native identity/consent, without changing the official CLI or persistent backend. Native migration and connection acceptance remain separate.";
  upstream = "https://github.com/pingdotgg/t3code/releases/tag/v0.1.6";
  removal = "The selected official Nixpkgs Darwin package ships the signed vendor GUI and passes signature, provider, encrypted-catalog/Keychain continuity and native connection checks without this integration; retire this fix, extraction helper and regression together.";
  reviewedRevision = "4a002bbb33286e165f7af5b4595879d184deed28";
  inputPath = [ "nixpkgs-t3code" ];
  affectedVersions = {
    from = "0.1.6";
    until = "0.1.7";
  };
  apply =
    package:
    assert lib.assertMsg (
      package.version == "0.1.6"
    ) "Review the signed T3 vendor release before updating";
    assert lib.assertMsg (
      package ? unwrapped && package ? resourceMonitor && package ? override
    ) "Expected official T3 package/override/provider wrapper contract";
    let
      appName = "T3 Code (Beta)";
      archive = pkgs.fetchurl {
        url = "https://github.com/pingdotgg/t3code/releases/download/v0.1.6/T3-Code-0.1.6-arm64.zip";
        hash = "sha256-GkXOqvyqqMWmL63LFr1CxJVQfFkcme0iOTQkCm6B9pk=";
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
        doInstallCheck = true;
        installPhase = builtins.readFile ./scripts/t3code-vendor-gui.sh;
        installCheckPhase = ''
          diff -qr --no-dereference "vendor/T3 Code (Beta).app" "$out/Applications/T3 Code (Beta).app"
          diff <(cd "vendor/T3 Code (Beta).app" && find . -printf '%P %m %l\n' | LC_ALL=C sort) \
            <(cd "$out/Applications/T3 Code (Beta).app" && find . -printf '%P %m %l\n' | LC_ALL=C sort)
        '';
        meta = package.meta // {
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
      inherit (package) pname version meta;
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
        test "$out/bin/t3" -ef ${lib.escapeShellArg "${package}/bin/t3"}
      '';
    };
}
