{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin system;

  zenTwilightUnwrapped = inputs.zen-browser.packages.${system}.twilight-unwrapped;

  darwinZenTwilightUnwrapped =
    (zenTwilightUnwrapped.override {
      # On Darwin, Home Manager writes policies through the macOS defaults
      # domain. Passing them to the package would mutate the signed app bundle.
      inherit (config.programs.zen-browser) enablePrivateDesktopEntry;
    }).overrideAttrs
      (old: {
        # Upstream re-signs the app bundle for AdGuard compatibility, but Nix's
        # Darwin sandbox blocks /usr/bin/codesign. Keep the package buildable.
        installPhase =
          builtins.replaceStrings
            [
              ''
                # Re-sign with correct identifier to maintain AdGuard compatibility
                # AdGuard uses code signing identifier (not CFBundleIdentifier) to recognize apps
                /usr/bin/codesign --force --deep --sign - \
                  --identifier "app.zen-browser.zen" \
                  "$out/Applications/Zen Browser (Twilight).app"

              ''
            ]
            [ "" ]
            old.installPhase;
      });
in
{
  imports = [
    inputs.zen-browser.homeModules.twilight
    ./blocking.nix
    ./acceleration.nix
    ./extensions.nix
    ./language.nix
    ./policies.nix
    ./search.nix
    ./user-js.nix
  ];

  programs.zen-browser = {
    enable = true;

    # Extra language packs can be used to fingerprint, so keep this minimal.
    languagePacks = [ "en-US" ];

    profiles.default = {
      id = 0;
      isDefault = true;
      name = "default";
    };

    unwrappedPackage = lib.mkIf isDarwin darwinZenTwilightUnwrapped;
  };
}
