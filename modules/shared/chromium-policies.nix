let
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

      inherit (cfg) extensionUpdateUrl;
      inherit (cfg) heliumExtensions;
      inherit (cfg) customFilterLists;
      catppuccinMochaThemeId = "bkkmolkhemgaeaeggcmfbghljjjoofoh";
      gruvboxDarkMediumThemeId = "ihennfdbghdiflogeancnalflhgmanop";
      browserTheme =
        {
          catppuccin-mocha = {
            name = "catppuccinMocha";
            id = catppuccinMochaThemeId;
          };
          gruvbox-dark-medium = {
            name = "gruvboxDarkMedium";
            id = gruvboxDarkMediumThemeId;
          };
        }
        .${config.appearance.theme} or null;
      chromiumSystemResolverPolicy = {
        DnsOverHttpsMode = cfg.dnsOverHttpsMode;
      };
      heliumUblockOriginId = "blockjmkbacgjkknlgpkjjiijinjdanf";
      bitwardenExtensionId = "nngceckbapebfimnlniiiahkandclblb";
      heliumUblockAssetsBootstrapLocation = "https://services.helium.imput.net/ubo/assets.json";

      extensionIds = builtins.attrValues heliumExtensions;

      forceInstallForcelist = map (extensionId: "${extensionId};${extensionUpdateUrl}") extensionIds;

      forceInstallExtensionSettings = builtins.listToAttrs (
        map (extensionId: {
          name = extensionId;
          value = {
            installation_mode = "force_installed";
            update_url = extensionUpdateUrl;
          };
        }) extensionIds
      );

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

      ublockCustomRules = builtins.readFile ./ublock-dynamic-filtering.txt;

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

        toOverwrite = {
          filters = [ ];
          filterLists = defaultFilterLists ++ customFilterLists;
        };
      };

      chromiumExtensionPolicies = {
        ${heliumUblockOriginId} = ublockOriginPolicy;
      };

      browserThemePolicy = lib.optionalAttrs (browserTheme != null) {
        ${browserTheme.id} = {
          installation_mode = "force_installed";
          update_url = extensionUpdateUrl;
        };
      };

      heliumPolicies = {
        BrowserSignin = 0;
        SyncDisabled = true;
        BrowserAddPersonEnabled = false;
        BrowserGuestModeEnabled = false;
        ProfilePickerOnStartupAvailability = 1;

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
        # DoH belongs to the local system resolver policy, not the browser. A
        # desktop-local override used to carry this setting; keeping it here makes
        # the behavior consistent for every Helium host.
        inherit (chromiumSystemResolverPolicy) DnsOverHttpsMode;

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

            inheritSharedPolicies = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Whether this target receives the shared Chromium policy set.
                Disable this for a distinct browser whose policy should be
                narrowly scoped rather than inheriting Helium-specific
                extensions and UX controls.
              '';
            };
          };
        }
      );

      enabledTargets = filterAttrs (_: target: target.enable) cfg.targets;
      browserPolicies =
        target: lib.optionalAttrs target.inheritSharedPolicies cfg.policies // target.policies;
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
      darwinPolicyDirectory = "/Library/Preferences";
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

      # Extension managed storage is only read from macOS MCX preferences. A
      # regular plist under /Library/Preferences is enough for browser policy,
      # but uBlock never receives it through chrome.storage.managed.
      darwinExtensionManagedPreferences =
        plistFormat.generate "chromium-extension-managed-preferences.plist"
          (
            listToAttrs (
              concatMap (
                target:
                mapAttrsToList (extensionId: extensionPolicy: {
                  name = "${target.darwinExtensionPolicyBundlePrefix}.${extensionId}";
                  value = lib.mapAttrs (_: value: {
                    state = "always";
                    inherit value;
                  }) extensionPolicy;
                }) target.extensionPolicies
              ) darwinExtensionPolicyTargets
            )
          );

      darwinExtensionPolicyCleanup = concatMapStringsSep "\n" (target: ''
        rm -f "${darwinPolicyDirectory}/${target.darwinExtensionPolicyBundlePrefix}".*.plist
      '') darwinExtensionPolicyTargets;

      # Chromium does not retain arbitrary files written directly to
      # /Library/Managed Preferences on current macOS releases. Clear the
      # previous best-effort files as policies now live in /Library/Preferences.
      darwinLegacyManagedPolicyCleanup = concatMapStringsSep "\n" (target: ''
        rm -f "/Library/Managed Preferences/${target.darwinBundleId}.plist"
        ${lib.optionalString (target.darwinExtensionPolicyBundlePrefix != null) ''
          rm -f "/Library/Managed Preferences/${target.darwinExtensionPolicyBundlePrefix}".*.plist
        ''}
      '') (attrValues darwinTargets);

      # Migrate away from the external-extension discovery files used before
      # force-install policy support. Keep the cleanup narrowly scoped to the
      # extension IDs this module owns.
      darwinLegacyExternalExtensionCleanup =
        concatMapStringsSep "\n"
          (
            directory:
            concatMapStringsSep "\n" (extensionId: ''
              rm -f "${directory}/${extensionId}.json"
            '') extensionIds
          )
          [
            "/Library/Application Support/Chromium/External Extensions"
            "/Library/Application Support/net.imput.helium/External Extensions"
          ];

      darwinActivation = concatMapStringsSep "\n" (target: ''
        install -m 0644 ${target.source} "${darwinPolicyDirectory}/${target.bundleId}.plist"
        chown root:wheel "${darwinPolicyDirectory}/${target.bundleId}.plist"
      '') (attrValues darwinPolicyPlists);

      darwinExtensionManagedPreferencesActivation =
        lib.optionalString (darwinExtensionPolicyTargets != [ ])
          ''
            /usr/bin/dscl /Local/Default -mcximport /Computers/localhost ${darwinExtensionManagedPreferences}
            /usr/bin/mcxrefresh -n ${lib.escapeShellArg config.system.primaryUser} || true
          '';
    in
    {
      options.programs.chromiumPolicies = {
        enable = mkEnableOption "system-level Chromium managed policies";

        dnsOverHttpsMode = mkOption {
          type = types.enum [
            "off"
            "automatic"
            "secure"
          ];
          default = "off";
          description = ''
            Managed Secure DNS mode for Chromium-family browsers. Set this to
            "off" when the operating-system resolver is the DNS authority.
          '';
        };

        extensionUpdateUrl = mkOption {
          type = types.str;
          default = "https://clients2.google.com/service/update2/crx";
          description = "Chrome Web Store update URL for managed Chromium extensions.";
        };

        heliumExtensions = mkOption {
          type = types.attrsOf types.str;
          default = {
            sponsorBlock = "mnjggcdmjocbbbhaepdhchncahnbgone";
            bitwarden = "nngceckbapebfimnlniiiahkandclblb";
            karakeep = "kgcjekpmcjjogibpjebkhaanilehneje";
            refinedGitHub = "hlepfoohegkhhmjieoechaddaejaokhf";
          }
          // lib.optionalAttrs (browserTheme != null) { ${browserTheme.name} = browserTheme.id; };
          description = "Named Chrome Web Store extension IDs managed for Helium.";
        };

        customFilterLists = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Extra uBlock Origin filter lists. The empty default keeps the
            extension's maintained stock list selection.
          '';
        };

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
              extensionPolicies = chromiumExtensionPolicies;
            };

            # Chrome can install the maintained Catppuccin and Gruvbox ports
            # directly. Carbon Neon deliberately leaves Chrome's native dark
            # UI unbranded instead of forcing an unrelated Web Store theme.
            targets.google-chrome = {
              enable = lib.mkDefault true;
              inheritSharedPolicies = false;
              linuxManagedPaths = [ "opt/chrome/policies/managed/nixos-system.json" ];
              darwinBundleId = "com.google.Chrome";
              policies = chromiumSystemResolverPolicy // {
                ExtensionInstallForcelist = [
                  "${bitwardenExtensionId};${extensionUpdateUrl}"
                ]
                ++ lib.optionals (browserTheme != null) [ "${browserTheme.id};${extensionUpdateUrl}" ];
                ExtensionSettings = {
                  ${bitwardenExtensionId} = {
                    installation_mode = "force_installed";
                    update_url = extensionUpdateUrl;
                  };
                }
                // browserThemePolicy;
              };
            };
          };
        }
        (mkIf (cfg.enable && isLinux) { environment.etc = nixosEtcEntries; })
        (mkIf (cfg.enable && isDarwin && darwinPolicyPlists != { }) {
          system.activationScripts.extraActivation.text = lib.mkAfter ''
            install -d -m 0755 "${darwinPolicyDirectory}"
            ${darwinLegacyManagedPolicyCleanup}
            ${darwinLegacyExternalExtensionCleanup}
            ${darwinExtensionPolicyCleanup}
            ${darwinActivation}
            ${darwinExtensionManagedPreferencesActivation}
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
