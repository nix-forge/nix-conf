let
  extensionUpdateUrl = "https://clients2.9oo91e.qjz9zk/service/update2/crx";
  heliumUblockOriginId = "blockjmkbacgjkknlgpkjjiijinjdanf";
  heliumUblockAssetsBootstrapLocation = "https://services.helium.imput.net/ubo/assets.json";

  chromiumExtensions = {
    # SponsorBlock for YouTube
    mnjggcdmjocbbbhaepdhchncahnbgone = { };

    # Bitwarden Password Manager
    nngceckbapebfimnlniiiahkandclblb = { };

    # Karakeep
    kgcjekpmcjjogibpjebkhaanilehneje = { };

    # Refined GitHub
    hlepfoohegkhhmjieoechaddaejaokhf = { };
  };

  extensionIds = builtins.attrNames chromiumExtensions;

  forceInstallForcelist = map (extensionId: "${extensionId};${extensionUpdateUrl}") extensionIds;

  forceInstallExtensionSettings = builtins.mapAttrs (_: _: {
    installation_mode = "force_installed";
    update_url = extensionUpdateUrl;
  }) chromiumExtensions;

  toUblockPairList =
    attrs:
    map (
      name:
      let
        value = attrs.${name};
      in
      [
        name
        (if builtins.isBool value then if value then "true" else "false" else toString value)
      ]
    ) (builtins.attrNames attrs);

  # Privacy filters
  privacyEssentials = "https://raw.githubusercontent.com/yokoffing/filterlists/main/privacy_essentials.txt";
  haegeziProMini = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.mini.txt";
  legitUrlShortener = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt";
  clearUrlsUbo = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/ClearURLs%20for%20uBo/clear_urls_uboified.txt";
  thirdPartyFonts = "https://raw.githubusercontent.com/yokoffing/filterlists/main/block_third_party_fonts.txt";

  # Annoyances filters
  yokoffingAnnoyances = "https://raw.githubusercontent.com/yokoffing/filterlists/main/annoyance_list.txt";
  browseWithoutLogin = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/BrowseWebsitesWithoutLoggingIn.txt";
  youTubeClearView = "https://raw.githubusercontent.com/yokoffing/filterlists/main/youtube_clear_view.txt";
  bypassPaywallsClean = "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt";
  antiPaywall = "https://raw.githubusercontent.com/liamengland1/miscfilters/master/antipaywall.txt";

  # Security filters
  mostAbusedTlds = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt";
  dandelionAntiMalware = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Dandelion%20Sprout's%20Anti-Malware%20List.txt";
  maliciousWebsiteBlocklist = "https://raw.githubusercontent.com/iam-py-test/my_filters_001/main/antimalware.txt";

  # All-purpose combo lists
  ublockComboList = "https://raw.githubusercontent.com/iam-py-test/uBlock-combo/main/list.txt";
  haegeziComboAltMini = "https://raw.githubusercontent.com/cbuijs/hagezi/refs/heads/main/combo/alt-suggested-mini/domains.top-n.adblock";

  # Extra optional filter lists
  youTubeShorts = "https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt";

  customFilterLists = [
    privacyEssentials
    haegeziProMini
    legitUrlShortener
    clearUrlsUbo
    thirdPartyFonts

    yokoffingAnnoyances
    browseWithoutLogin
    youTubeClearView
    bypassPaywallsClean
    antiPaywall

    mostAbusedTlds
    dandelionAntiMalware
    maliciousWebsiteBlocklist

    ublockComboList
    haegeziComboAltMini

    youTubeShorts
  ];

  ublockCustomRules = ''
    * * 3p-script block
    * * 3p-frame block

    * challenges.cloudflare.com * noop
    * www.google.com * noop
    * www.gstatic.com * noop
    * hcaptcha.com * noop
    * recaptcha.net * noop

    * youtube.com * 3p-script noop

    github.com * 3p-script noop
    github.com * 3p-frame noop

    www.reddit.com * 3p-script noop
    www.reddit.com * 3p-frame noop

    edstem.org * 3p-script noop
    edstem.org * 3p-frame noop

    accounts.google.com * 3p-script noop

    chatgpt.com * 3p-script noop
    chatgpt.com * 3p-frame noop

    home-manager-options.extranix.com * 3p-script noop

    www.instagram.com * 3p-script noop
    www.instagram.com * 3p-frame noop

    x.com * 3p-frame noop
    x.com * 3p-script noop

    www.linkedin.com * 3p-script noop
    www.linkedin.com * 3p-frame noop

    www.doordash.com * 3p-script noop
    www.doordash.com * 3p-frame noop

    www.gradescope.com * 3p-frame noop
    www.gradescope.com * 3p-script noop

    myworkdayjobs.com * 3p-script noop
    myworkdayjobs.com * 3p-frame noop

    www.instacart.com * 3p-script noop
    www.instacart.com * 3p-frame noop

    grammarly.com * 3p-script noop
    grammarly.com * 3p-frame noop

    canvas.cornell.edu * 3p-script noop
    canvas.cornell.edu * 3p-frame noop

    cornell.app.box.com * 3p-frame noop
    cornell.app.box.com * 3p-script noop

    pcpartpicker.com * 3p-frame noop
    pcpartpicker.com * 3p-script noop

    gemini.google.com * 3p-frame noop
    gemini.google.com * 3p-script noop

    digital.fidelity.com * 3p-frame noop
    digital.fidelity.com * 3p-script noop
  '';

  defaultFilterLists = [
    "user-filters"

    # Helium's own uBO service publishes browser-specific lists for cleanups and
    # webcompat. Keep these alongside the upstream uBlock lists.
    "helium-annoyances"
    "helium-unbreak"

    "ublock-filters"
    "ublock-badware"
    "ublock-privacy"
    "ublock-quick-fixes"
    "ublock-unbreak"

    "easylist"
    "adguard-generic"

    "easyprivacy"
    "adguard-spyware-url"

    "urlhaus-1"

    "plowe-0"

    "fanboy-cookiemonster"

    "adguard-cookies"
    "ublock-cookies-easylist"
    "easylist-newsletters"
    "easylist-notifications"
    "ublock-annoyances"
  ];

  ublockAdminSettings = {
    assetsBootstrapLocation = heliumUblockAssetsBootstrapLocation;
    dynamicFilteringString = ublockCustomRules;
    selectedFilterLists = defaultFilterLists ++ customFilterLists;
    userSettings = {
      prefetchingDisabled = true;
      hyperlinkAuditingDisabled = true;
      cnameUncloakEnabled = true;
      autoUpdate = true;
      advancedUserEnabled = true;
      dynamicFilteringEnabled = true;
      importedLists = customFilterLists;
    };
  };

  ublockOriginPolicy = {
    # uBO's Chromium managed-storage schema requires a JSON string in backup
    # format. The backup still carries Helium's assets bootstrap URL for uBO's
    # admin restore path while keeping chrome://policy validation clean.
    adminSettings = builtins.toJSON ublockAdminSettings;

    userSettings = toUblockPairList {
      prefetchingDisabled = true;
      hyperlinkAuditingDisabled = true;
      cnameUncloakEnabled = true;
      autoUpdate = true;
      advancedUserEnabled = true;
      dynamicFilteringEnabled = true;
    };

    advancedSettings = toUblockPairList {
      autoUpdateDelayAfterLaunch = 37;
      updateAssetBypassBrowserCache = true;
    };

    toOverwrite = {
      filters = [ ];
      filterLists = defaultFilterLists ++ customFilterLists;
    };
  };

  chromiumExtensionPolicies = {
    ${heliumUblockOriginId} = ublockOriginPolicy;
  };

  heliumPolicies = {
    BrowserSignin = 0;
    SyncDisabled = true;

    UrlKeyedAnonymizedDataCollectionEnabled = false;
    SearchSuggestEnabled = false;
    AlternateErrorPagesEnabled = false;

    PasswordManagerEnabled = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    PaymentMethodQueryEnabled = false;

    HttpsOnlyMode = "force_enabled";
    SafeBrowsingProtectionLevel = 1;
    SafeBrowsingExtendedReportingEnabled = false;
    DnsOverHttpsMode = "automatic";

    DefaultCookiesSetting = 1;
    BlockThirdPartyCookies = true;

    ShowHomeButton = true;
    BookmarkBarEnabled = false;
    DefaultBrowserSettingEnabled = false;
    BackgroundModeEnabled = false;

    SpellcheckEnabled = true;
    SpellcheckLanguage = [ "en-US" ];

    ExtensionInstallAllowlist = extensionIds;
    ExtensionInstallForcelist = forceInstallForcelist;
    ExtensionSettings = forceInstallExtensionSettings;
  };

  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.chromiumPolicies;
      inherit (lib)
        attrValues
        concatMap
        concatMapStringsSep
        filterAttrs
        listToAttrs
        mapAttrs'
        mapAttrsToList
        mkEnableOption
        mkIf
        mkMerge
        mkOption
        nameValuePair
        types
        ;

      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

      targetType = types.submodule (
        { name, ... }: {
          options = {
            enable = mkEnableOption "Chromium policy target ${name}";

            linuxManagedPaths = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "chromium/policies/managed/${name}-system.json" ];
              description = ''
                Relative paths below /etc where NixOS should write this
                target's managed Chromium policy JSON.
              '';
            };

            darwinBundleId = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "net.imput.helium";
              description = ''
                macOS application bundle identifier used for the managed
                preferences plist.
              '';
            };

            darwinExtensionPolicyBundlePrefix = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "net.imput.helium.extensions";
              description = ''
                macOS managed preference domain prefix used for extension
                managed storage policies.
              '';
            };

            darwinExternalExtensionDirs = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [
                "/Library/Application Support/Chromium/External Extensions"
                "/Library/Application Support/net.imput.helium/External Extensions"
              ];
              description = ''
                macOS external extension directories where JSON install hints
                should be written for this browser.
              '';
            };

            policies = mkOption {
              type = types.attrs;
              default = { };
              description = "Target-specific Chromium policy overrides.";
            };

            extensionPolicies = mkOption {
              type = types.attrsOf types.attrs;
              default = { };
              description = "Managed storage policies keyed by Chromium extension ID.";
            };
          };
        }
      );

      enabledTargets = filterAttrs (_: target: target.enable) cfg.targets;
      browserPolicies = target: cfg.policies // target.policies;
      linuxTargetPolicies =
        target:
        (browserPolicies target)
        // lib.optionalAttrs (target.extensionPolicies != { }) {
          "3rdparty".extensions = target.extensionPolicies;
        };

      nixosEtcEntries = listToAttrs (
        concatMap (
          target:
          map (path: {
            name = path;
            value.text = builtins.toJSON (linuxTargetPolicies target);
          }) target.linuxManagedPaths
        ) (attrValues enabledTargets)
      );

      darwinTargets = filterAttrs (_: target: target.darwinBundleId != null) enabledTargets;
      plistFormat = pkgs.formats.plist { };
      darwinPolicyPlists = mapAttrs' (
        name: target:
        nameValuePair name {
          bundleId = target.darwinBundleId;
          source = plistFormat.generate "${target.darwinBundleId}.plist" (browserPolicies target);
        }
      ) darwinTargets;

      darwinExtensionPolicyTargets = attrValues (
        filterAttrs (
          _: target: target.darwinExtensionPolicyBundlePrefix != null && target.extensionPolicies != { }
        ) enabledTargets
      );

      darwinExtensionPolicyPlists = concatMap (
        target:
        mapAttrsToList (extensionId: extensionPolicy: {
          bundleId = "${target.darwinExtensionPolicyBundlePrefix}.${extensionId}";
          source = plistFormat.generate "${target.darwinExtensionPolicyBundlePrefix}.${extensionId}.plist" extensionPolicy;
        }) target.extensionPolicies
      ) darwinExtensionPolicyTargets;

      darwinExtensionPolicyBundleIds = map (target: target.bundleId) darwinExtensionPolicyPlists;

      darwinExternalExtensionTargets = attrValues (
        filterAttrs (
          _: target: target.darwinExternalExtensionDirs != [ ] && (browserPolicies target) ? ExtensionSettings
        ) enabledTargets
      );

      darwinExternalExtensionFiles = concatMap (
        target:
        concatMap (
          directory:
          mapAttrsToList (extensionId: extensionSettings: {
            inherit directory extensionId;
            source = pkgs.writeText "${extensionId}.json" (
              builtins.toJSON { external_update_url = extensionSettings.update_url; }
            );
          }) (browserPolicies target).ExtensionSettings
        ) target.darwinExternalExtensionDirs
      ) darwinExternalExtensionTargets;

      darwinExternalExtensionDirs = builtins.attrNames (
        builtins.listToAttrs (
          map (file: {
            name = file.directory;
            value = true;
          }) darwinExternalExtensionFiles
        )
      );

      darwinExtensionPolicyCleanup = concatMapStringsSep "\n" (target: ''
        for oldPolicy in "/Library/Managed Preferences/${target.darwinExtensionPolicyBundlePrefix}".*.plist; do
          [ -e "$oldPolicy" ] || continue
          case "$oldPolicy" in
        ${concatMapStringsSep "\n" (
          bundleId: ''"/Library/Managed Preferences/${bundleId}.plist") ;;''
        ) darwinExtensionPolicyBundleIds}
            *) rm -f "$oldPolicy" ;;
          esac
        done
      '') darwinExtensionPolicyTargets;

      darwinExternalExtensionCleanup = concatMapStringsSep "\n" (directory: ''
        for oldExtension in "${directory}"/*.json; do
          [ -e "$oldExtension" ] || continue
          case "$oldExtension" in
        ${concatMapStringsSep "\n" (
          file: ''"${file.directory}/${file.extensionId}.json") ;;''
        ) darwinExternalExtensionFiles}
            *) rm -f "$oldExtension" ;;
          esac
        done
      '') darwinExternalExtensionDirs;

      darwinActivation = concatMapStringsSep "\n" (target: ''
        install -m 0644 ${target.source} "/Library/Managed Preferences/${target.bundleId}.plist"
        chown root:wheel "/Library/Managed Preferences/${target.bundleId}.plist"
      '') (attrValues darwinPolicyPlists ++ darwinExtensionPolicyPlists);

      darwinExternalExtensionActivation = concatMapStringsSep "\n" (target: ''
        install -d -m 0755 "${target.directory}"
        chown root:wheel "${target.directory}"
        install -m 0644 ${target.source} "${target.directory}/${target.extensionId}.json"
        chown root:wheel "${target.directory}/${target.extensionId}.json"
      '') darwinExternalExtensionFiles;
    in
    {
      options.programs.chromiumPolicies = {
        enable = mkEnableOption "system-level Chromium managed policies";

        policies = mkOption {
          type = types.attrs;
          default = heliumPolicies;
          description = "Shared Chromium policies applied to every enabled target.";
        };

        targets = mkOption {
          type = types.attrsOf targetType;
          default = { };
          description = "Chromium-family applications to receive managed policies.";
        };
      };

      config = mkMerge [
        {
          programs.chromiumPolicies = {
            enable = lib.mkDefault true;

            targets.helium = {
              enable = lib.mkDefault true;
              linuxManagedPaths = [
                "chromium/policies/managed/helium-system.json"
                "helium/policies/managed/helium-system.json"
              ];
              darwinBundleId = "net.imput.helium";
              darwinExtensionPolicyBundlePrefix = "net.imput.helium.extensions";
              darwinExternalExtensionDirs = [
                # Chromium's macOS external-extension provider keys off
                # CrProductDirName. Helium omits that Info.plist key, so an
                # unbranded Chromium build falls back to this product dir.
                "/Library/Application Support/Chromium/External Extensions"
                # Helium uses this bundle-id directory for its user data and
                # managed preference domain, so keep a matching install hint
                # here too in case upstream adds CrProductDirName later.
                "/Library/Application Support/net.imput.helium/External Extensions"
              ];
              extensionPolicies = chromiumExtensionPolicies;
            };
          };
        }
        (mkIf (cfg.enable && isLinux) { environment.etc = nixosEtcEntries; })
        (mkIf (cfg.enable && isDarwin && darwinPolicyPlists != { }) {
          system.activationScripts.extraActivation.text = lib.mkAfter ''
            install -d -m 0755 "/Library/Managed Preferences"
            ${darwinExtensionPolicyCleanup}
            ${darwinActivation}
            ${darwinExternalExtensionCleanup}
            ${darwinExternalExtensionActivation}
            killall cfprefsd 2>/dev/null || true
          '';
        })
      ];
    };
in
{
  nixos = module;
  darwin = module;
}
