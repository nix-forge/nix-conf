{
  config,
  inputs,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  inherit (config.programs.browserSuite)
    blocking
    geckoPolicies
    scrolling
    systemResolverPolicy
    ;
  inherit (config.programs.browserSuite.shared) profile search ublock;
  inherit (config.programs.browserSuite.shared.geckoInstallRegistry) reconciler;
  extensionGroups = config.programs.browserSuite.extensions;
  extensions = extensionGroups.shared // extensionGroups.zen;
  defaultProfile = lib.findFirst (profileConfig: profileConfig.isDefault) null (
    lib.attrValues config.programs.zen-browser.profiles
  );
  darwinConfigPath = "${config.home.homeDirectory}/Library/Application Support/Zen";
  reconcileInstallRegistry = lib.escapeShellArgs [
    (lib.getExe reconciler)
    "--profiles-registry"
    "${darwinConfigPath}/profiles.ini"
    "--install-registry"
    "${darwinConfigPath}/installs.ini"
    "--default-profile"
    "Profiles/${defaultProfile.path}"
  ];
  extensionPolicies = {
    ExtensionSettings = myLib.browser.extensions.mkPolicies extensions;
  };
  ublockPolicies = lib.optionalAttrs (extensions ? ublockOrigin) {
    "3rdparty".Extensions.${extensions.ublockOrigin.id} = myLib.browser.ublock.mkPolicy {
      inherit (blocking) customFilterLists;
      inherit (ublock) defaultFilterLists settings;
    };
  };
in
{
  imports = [
    inputs.zen-browser.homeModules.beta
    ../shared
    ./shopping.nix
  ];

  programs.zen-browser = {
    enable = true;
    enablePrivateDesktopEntry = true;
    darwin.packageMode = "signed";
    policies = systemResolverPolicy // geckoPolicies // extensionPolicies // ublockPolicies;

    profiles.default = {
      id = 0;
      isDefault = true;
      name = "default";
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
      run ${reconcileInstallRegistry}
    ''
  );
}
