{
  config,
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
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  extensionGroups = config.programs.browserSuite.extensions;
  extensions = extensionGroups.shared // extensionGroups.firefox;
  defaultProfile = lib.findFirst (profileConfig: profileConfig.isDefault) null (
    lib.attrValues config.programs.firefox.profiles
  );
  darwinConfigPath = "${config.home.homeDirectory}/Library/Application Support/Firefox";
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
  imports = [ ../shared ];

  programs.firefox = {
    enable = true;
    # Policies live in the macOS defaults domain, so Darwin does not need a
    # wrapFirefox rebuild that strips Mozilla's application signature.
    package = lib.mkIf isDarwin pkgs.firefox-bin-unwrapped;
    policies = systemResolverPolicy // geckoPolicies // extensionPolicies // ublockPolicies;

    profiles.default = {
      id = 0;
      isDefault = true;
      settings = profile.commonSettings // profile.scrolling.${scrolling};
      search = {
        force = true;
        engines = search.commonEngines;
      };
    };
  };

  home.activation.reconcileFirefoxInstallRegistry = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${reconcileInstallRegistry}
    ''
  );
}
