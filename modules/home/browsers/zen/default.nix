{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  suite = config.programs.browserSuite;
  inherit (suite) scrolling;
  inherit (suite.shared) profile search;
  gecko = (import ../shared/.gecko.nix { inherit lib; }) {
    inherit suite;
    browser = "zen";
    inherit (config.programs.zen-browser) profiles;
    configDirectory = "${config.home.homeDirectory}/Library/Application Support/Zen";
  };
in
{
  imports = [
    inputs.zen-browser.homeModules.beta
    ../shared
    ./shopping.nix
    {
      options.programs.zen-browser.package = lib.mkOption {
        apply =
          package:
          if pkgs.stdenv.hostPlatform.isDarwin && package != null then
            (import ../../../../overlays/temporary { inherit inputs pkgs; }).apply "zen-darwin-app-metadata"
              package
          else
            package;
      };
    }
  ];

  programs.zen-browser = {
    enable = true;
    enablePrivateDesktopEntry = true;
    darwin.packageMode = "signed";
    inherit (gecko) policies;

    profiles.default = {
      id = 0;
      isDefault = true;
      name = "default";
      userContent = lib.mkAfter (builtins.readFile ../shared/emoji-presentation.css);
      settings =
        profile.commonSettings
        // profile.scrolling.${scrolling}
        // {
          "zen.theme.hide-unified-extensions-button" = false;
          "zen.window-sync.enabled" = true;
          "zen.window-sync.sync-only-pinned-tabs" = true;
          "zen.workspaces.continue-where-left-off" = true;
        };
      search = {
        force = true;
        engines = search.commonEngines;
      };
    };
  };

  # Gecko keys installs.ini by application location. Old Zen package paths can
  # leave an installation ID pointing at a profile that Home Manager no longer
  # registers, which makes Zen stop at its "Profile Missing" dialog. Keep the
  # install IDs, but make each one select the declared default profile.
  home.activation.reconcileZenInstallRegistry = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${gecko.reconcileInstallRegistry}
    ''
  );
}
