{ modules, inputs, ... }:
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
in
{
  system = "aarch64-darwin";
  hostName = "Ian-MBP";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
  };

  nixpkgsArgs = {
    overlays = [
      inputs.nixpkgs-personal.overlays.default
      actualServerCaseFixOverlay
    ];
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    { system.primaryUser = "ianmh"; }
    # Original nix-darwin compatibility generation for this installation.
    # Raising this is a migration decision, not a routine upgrade.
    { system.stateVersion = 6; }

    ## Base
    determinate
    nix-settings
    registry
    cache
    chromium-policies
    nixSeal
    ./nix-seal.nix
    ./local/firewall.nix

    security
    stylix
    fonts
  ];

  homes.ianmh = {
    config = "ianmh@macbook-pro-m4";
    user = {
      description = "Ian Holloway";
      shell = inputs.nixpkgs.legacyPackages.aarch64-darwin.nushell;
    };
  };
}
