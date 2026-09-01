let
  homeModule =
    {
      lib,
      pkgs ? null,
      config,
      ...
    }:
    let
      isDarwin = pkgs != null && pkgs.stdenv.hostPlatform.isDarwin;
      browserTheme =
        {
          catppuccin-mocha = {
            name = "catppuccinMocha";
            id = "bkkmolkhemgaeaeggcmfbghljjjoofoh";
          };
          gruvbox-dark-medium = {
            name = "gruvboxDarkMedium";
            id = "ihennfdbghdiflogeancnalflhgmanop";
          };
        }
        .${config.appearance.theme} or null;
    in
    {
      options.programs.browserPolicy = with lib; {
        systemResolver = {
          firefox = mkOption {
            type = types.attrs;
            default = {
              DNSOverHTTPS = {
                Enabled = false;
                Locked = true;
              };
            };
            description = ''
              Firefox enterprise policy that keeps DNS ownership with the
              operating-system resolver.
            '';
          };

        };

        chromium = {
          extensionUpdateUrl = mkOption {
            type = types.str;
            default = "https://clients2.google.com/service/update2/crx";
            description = "Chrome Web Store update URL for Chromium extensions.";
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
        };

        firefox.policies = mkOption {
          type = types.attrs;
          default = {
            AppAutoUpdate = false;
            ManualAppUpdateOnly = true;
            DisableFeedbackCommands = true;
            DisableSetDesktopBackground = true;
            DisableDeveloperTools = false;
            DisableProfileRefresh = false;
            DisableProfileImport = true;
            DisablePrivateBrowsing = false;
            DisplayBookmarksToolbar = "never";
            DisableFirefoxAccounts = true;
            PasswordManagerEnabled = false;
            AutofillAddressEnabled = false;
            AutofillCreditCardEnabled = false;
            DisableMasterPasswordCreation = true;
            DisablePasswordReveal = true;
            DisablePocket = true;
            DisableTelemetry = true;
            HardwareAcceleration = true;
            DisableFirefoxStudies = true;
            DisableFirefoxScreenshots = false;
            NoDefaultBookmarks = true;
            SearchSuggestEnabled = false;
            DisableFormHistory = true;
            DontCheckDefaultBrowser = true;
            SkipTermsOfUse = true;
            HttpsOnlyMode = "force_enabled";
            EnterprisePoliciesEnabled = isDarwin;
            FirefoxHome = {
              Search = true;
              TopSites = false;
              SponsoredTopSites = false;
              SponsoredPocket = false;
              SponsoredStories = false;
              Highlights = false;
              Pocket = false;
              Snippets = false;
              Locked = true;
            };
            UserMessaging = {
              WhatsNew = false;
              ExtensionRecommendations = false;
              FeatureRecommendations = false;
              SkipOnboarding = true;
              MoreFromMozilla = false;
              Locked = true;
            };
            FirefoxSuggest = {
              WebSuggestions = false;
              SponsoredSuggestions = false;
              ImproveSuggest = false;
              Locked = true;
            };
            ExtensionUpdate = true;
          };
          description = ''
            Enterprise policies shared by Firefox-derived browsers. Resolver
            policy remains separate so it can be coordinated with the host.
          '';
        };

        blocking = {
          customFilterLists = mkOption {
            type = types.listOf types.str;
            default = [
              "https://raw.githubusercontent.com/yokoffing/filterlists/main/privacy_essentials.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.mini.txt"
              "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt"
              "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/ClearURLs%20for%20uBo/clear_urls_uboified.txt"
              "https://raw.githubusercontent.com/yokoffing/filterlists/main/block_third_party_fonts.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt"
              "https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt"
            ];
            description = ''
              Extra uBlock Origin lists shared by the Chromium and Zen browser
              policy modules.
            '';
          };

          ublock = {
            dynamicFilteringRules = mkOption {
              type = types.lines;
              default = ''
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
              description = "uBlock Origin dynamic filtering rules shared by Firefox and Zen.";
            };

            userSettings = mkOption {
              type = types.attrs;
              default = {
                prefetchingDisabled = true;
                hyperlinkAuditingDisabled = true;
                cnameUncloakEnabled = true;
                autoUpdate = true;
                advancedUserEnabled = true;
                dynamicFilteringEnabled = true;
              };
              description = "uBlock Origin user settings shared by Firefox and Zen.";
            };

            advancedSettings = mkOption {
              type = types.attrs;
              default = {
                autoUpdateDelayAfterLaunch = 10;
                updateAssetBypassBrowserCache = true;
                filterAuthorMode = true;
              };
              description = "uBlock Origin advanced settings shared by Firefox and Zen.";
            };
          };
        };
      };
    };

  mkAttachedHomeModule =
    {
      lib,
      osConfig ? null,
      ...
    }@args:
    let
      systemChromiumPolicies =
        if osConfig == null then null else lib.attrByPath [ "programs" "chromiumPolicies" ] null osConfig;
    in
    (homeModule args)
    // lib.optionalAttrs (systemChromiumPolicies != null) {
      # Chromium-family managed policies have to be installed by the OS in
      # administrator-owned locations. Reuse their extension metadata in the
      # attached Home Manager profile, without making Firefox or Zen policy a
      # system concern. Standalone homes retain the portable defaults above.
      config.programs.browserPolicy = {
        chromium = {
          extensionUpdateUrl = lib.mkDefault systemChromiumPolicies.extensionUpdateUrl;
          heliumExtensions = lib.mkDefault systemChromiumPolicies.heliumExtensions;
        };
        blocking.customFilterLists = lib.mkDefault systemChromiumPolicies.customFilterLists;
      };
    };
in
{
  # Firefox/Zen policies and Home Manager browser configuration do not need
  # privileged system writes. Chromium's required system policy integration is
  # deliberately implemented in shared/chromium-policies.nix instead.
  homeManager = mkAttachedHomeModule;
}
