{ modules, ... }:
let
  actualServerCaseFixOverlay = _final: prev: {
    actual-server = prev.actual-server.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        ln -s themes~nix~case~hack~1 packages/component-library/src/themes
        mkdir -p packages/desktop-client/src/style/themes
        cp \
          packages/component-library/src/themes~nix~case~hack~1/dark.css \
          packages/component-library/src/themes~nix~case~hack~1/light.css \
          packages/component-library/src/themes~nix~case~hack~1/midnight.css \
          packages/component-library/src/themes~nix~case~hack~1/palette.css \
          packages/desktop-client/src/style/themes/
        substituteInPlace packages/desktop-client/src/style/theme.tsx \
          --replace-fail "@actual-app/components/themes/dark.css?inline" "./themes/dark.css?inline" \
          --replace-fail "@actual-app/components/themes/light.css?inline" "./themes/light.css?inline" \
          --replace-fail "@actual-app/components/themes/midnight.css?inline" "./themes/midnight.css?inline" \
          --replace-fail "@actual-app/components/themes/palette.css?inline" "./themes/palette.css?inline"
      '';
    });
  };

  #   darwinOpenSslTestOverlay = final: prev: {
  #     openssl = prev.openssl.overrideAttrs (old: {
  #       postPatch =
  #         (old.postPatch or "")
  #         + final.lib.optionalString final.stdenv.hostPlatform.isDarwin ''
  #           rm -f test/recipes/70-test_sslmessages.t
  #         '';
  #     });
  #   };
in
{
  system = "aarch64-darwin";
  # darwinSdkVersion = "15.5";
  # darwinMinVersion = "15.4";
  hostName = "Ian-MBP";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    overlays = [ actualServerCaseFixOverlay ];
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    { system.primaryUser = "ianmh"; }

    ## Base
    meta
    determinate
    nix-settings
    registry
    cache
    chromium-policies
    agenix

    ## Users
    home-manager
    users

    security
    stylix
    fonts
  ];
}
