{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  cfg = config.programs.browserSuite;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

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

  systemChromiumPolicies =
    if osConfig == null then null else lib.attrByPath [ "programs" "chromiumPolicies" ] null osConfig;

  selectedBrowser =
    if cfg.defaultBrowser == "firefox" then
      {
        appName = "Firefox";
        command = "firefox";
        desktopFile = "firefox.desktop";
        handler = "firefox";
      }
    else if cfg.defaultBrowser == "zen" then
      let
        package = config.programs.zen-browser.package;
      in
      {
        appName = package.applicationName or "Zen Browser (Beta)";
        command = package.meta.mainProgram or "zen-beta";
        desktopFile = "zen-beta.desktop";
        handler = "zen";
      }
    else
      null;

  darwinAppPath =
    if selectedBrowser == null then
      "__no-default-browser__"
    else
      let
        app = "${selectedBrowser.appName}.app";
      in
      if config.targets.darwin.copyApps.enable then
        "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/${app}"
      else if config.targets.darwin.linkApps.enable then
        "${config.home.homeDirectory}/${config.targets.darwin.linkApps.directory}/${app}"
      else
        "__managed-app-linking-disabled__";

  refreshDeps = [
    "installPackages"
  ]
  ++ lib.optionals config.targets.darwin.copyApps.enable [ "copyApps" ]
  ++ lib.optionals (!config.targets.darwin.copyApps.enable) [ "linkGeneration" ];

  defaultBrowserHelper = pkgs.replaceVarsWith {
    name = "hm-set-default-browser";
    src = ./default-browser.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      awkExe = lib.getExe pkgs.gawk;
      defaultBrowserExe = lib.getExe pkgs.defaultbrowser;
      appPath = darwinAppPath;
      appLabel = if selectedBrowser == null then "browser" else selectedBrowser.appName;
      handler = if selectedBrowser == null then "none" else selectedBrowser.handler;
      lsregisterExe = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
      plistBuddyExe = "/usr/libexec/PlistBuddy";
    };
  };

  browserMimeAssociations =
    if selectedBrowser == null then
      { }
    else
      builtins.listToAttrs (
        map
          (mime: {
            name = mime;
            value = lib.mkDefault selectedBrowser.desktopFile;
          })
          [
            "application/xhtml+xml"
            "text/html"
            "x-scheme-handler/http"
            "x-scheme-handler/https"
          ]
      );
in
{
  imports = [
    ./bitwarden-native-messaging.nix
    ./extensions.nix
    ./install-registry.nix
    ./profile.nix
    ./search.nix
    ./ublock.nix
  ];

  options.programs.browserSuite = with lib; {
    defaultBrowser = mkOption {
      type = types.nullOr (
        types.enum [
          "firefox"
          "zen"
        ]
      );
      default = null;
      description = "Browser that owns HTTP and HTTPS links for this home.";
    };

    scrolling = mkOption {
      type = types.enum [
        "default"
        "instant"
        "natural"
        "sharpen"
        "smooth"
      ];
      default = "default";
      description = "Shared Gecko scrolling profile.";
    };

    systemResolverPolicy = mkOption {
      type = types.attrs;
      default = { };
      description = "Firefox DNS policy supplied only when the host owns DNS resolution.";
    };

    geckoPolicies = mkOption {
      type = types.attrs;
      default = {
        DisableAppUpdate = true;
        DisableFirefoxStudies = true;
        DisableSetDesktopBackground = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = false;
          Category = "strict";
          BaselineExceptions = true;
          ConvenienceExceptions = true;
        };
        ExtensionUpdate = true;
        HttpsOnlyMode = "enabled";
        SkipTermsOfUse = true;
        FirefoxHome = {
          SponsoredTopSites = false;
          SponsoredPocket = false;
          SponsoredStories = false;
        };
        FirefoxSuggest = {
          SponsoredSuggestions = false;
          ImproveSuggest = false;
        };
        UserMessaging = {
          ExtensionRecommendations = false;
          FeatureRecommendations = false;
          MoreFromMozilla = false;
          SkipOnboarding = true;
        };
      };
      description = "Conservative enterprise policy baseline for Firefox-derived browsers.";
    };

    chromium = {
      extensionUpdateUrl = mkOption {
        type = types.str;
        default = "https://clients2.google.com/service/update2/crx";
        description = "Chrome Web Store update URL used by the Helium adapter.";
      };

      heliumExtensions = mkOption {
        type = types.attrsOf types.str;
        default = {
          sponsorBlock = "mnjggcdmjocbbbhaepdhchncahnbgone";
          bitwarden = "nngceckbapebfimnlniiiahkandclblb";
          karakeep = "kgcjekpmcjjogibpjebkhaanilehneje";
          refinedGitHub = "hlepfoohegkhhmjieoechaddaejaokhf";
        }
        // optionalAttrs (browserTheme != null) { ${browserTheme.name} = browserTheme.id; };
        description = "Named Chrome Web Store extension IDs used by Helium.";
      };
    };

    blocking.customFilterLists = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra uBlock Origin lists for every configured browser. The empty
        default keeps uBlock's maintained stock list selection.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.optionalAttrs (systemChromiumPolicies != null) {
      programs.browserSuite = {
        chromium = {
          extensionUpdateUrl = lib.mkDefault systemChromiumPolicies.extensionUpdateUrl;
          heliumExtensions = lib.mkDefault systemChromiumPolicies.heliumExtensions;
        };
        blocking.customFilterLists = lib.mkDefault systemChromiumPolicies.customFilterLists;
      };
    })

    {
      assertions = [
        {
          assertion = cfg.defaultBrowser != "firefox" || config.programs.firefox.enable;
          message = "programs.browserSuite.defaultBrowser is firefox, but Firefox is disabled.";
        }
        {
          assertion = cfg.defaultBrowser != "zen" || config.programs.zen-browser.enable;
          message = "programs.browserSuite.defaultBrowser is zen, but Zen Browser is disabled.";
        }
      ];
    }

    (lib.mkIf (cfg.defaultBrowser != null) { home.sessionVariables.BROWSER = selectedBrowser.command; })

    (lib.mkIf (isLinux && cfg.defaultBrowser != null) {
      xdg.mimeApps = {
        enable = true;
        associations.added = browserMimeAssociations;
        defaultApplications = browserMimeAssociations;
      };
    })

    (lib.mkIf (isDarwin && cfg.defaultBrowser != null) {
      home.activation.setDefaultBrowser = lib.hm.dag.entryAfter refreshDeps ''
        ${lib.getExe' defaultBrowserHelper "hm-set-default-browser"}
      '';
    })
  ];
}
