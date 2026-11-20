{
  config,
  lib,
  osConfig ? null,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.programs.browserSuite;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  systemChromiumPolicies =
    if osConfig == null then null else lib.attrByPath [ "programs" "chromiumPolicies" ] null osConfig;

  selectedBrowser =
    if cfg.defaultBrowser == "firefox" then
      {
        appName = "Firefox";
        command = "firefox";
        desktopFile = "firefox.desktop";
      }
    else if cfg.defaultBrowser == "zen" then
      let
        package = config.programs.zen-browser.package;
      in
      {
        appName = package.applicationName or "Zen Browser (Beta)";
        command = package.meta.mainProgram or "zen-beta";
        desktopFile = "zen-beta.desktop";
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

  setDefaultBrowser =
    pkgs.runCommandCC "hm-set-default-browser"
      {
        nativeBuildInputs = [ pkgs.swift ];
        meta.mainProgram = "hm-set-default-browser";
        meta.platforms = lib.platforms.darwin;
      }
      (
        myLib.writers.renderBashText { inherit pkgs; }
          {
            name = "build-default-browser-helper.sh";
            text = ''
              # shellcheck shell=bash
              # Variables and functions are supplied by the owning activation or build phase.
              # shellcheck disable=SC2154
              mkdir -p "$out/bin"
              swiftc -target @swiftTarget@ -swift-version 6 -warnings-as-errors -parse-as-library -O @set_default_browser_swift@ -o "$out/bin/hm-set-default-browser"

              # Missing arguments return before the helper changes any browser registration.
              if "$out/bin/hm-set-default-browser" >usage.log 2>&1; then
                echo "Default browser helper unexpectedly accepted missing arguments" >&2
                exit 1
              else
                status=$?
              fi
              if [[ $status != 2 || $(cat usage.log) != 'usage: hm-set-default-browser APP LABEL LSREGISTER' ]]; then
                cat usage.log >&2
                echo "Default browser helper failed its no-argument usage check" >&2
                exit 1
              fi
            '';
          }
          {
            set_default_browser_swift = ./set-default-browser.swift;
            swiftTarget = lib.escapeShellArg "${pkgs.stdenv.hostPlatform.darwinArch}-apple-macosx${pkgs.stdenv.hostPlatform.darwinMinVersion}";
          }
      );

  browserMimeAssociations =
    if selectedBrowser == null then
      { }
    else
      lib.genAttrs [
        "application/xhtml+xml"
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ] (_: lib.mkDefault selectedBrowser.desktopFile);

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
      type = types.attrsOf (pkgs.formats.json { }).type;
      default = { };
      description = "Firefox DNS policy supplied only when the host owns DNS resolution.";
    };

    geckoPolicies = mkOption {
      type = types.attrsOf (pkgs.formats.json { }).type;
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
        };
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
        run ${
          lib.escapeShellArgs [
            (lib.getExe setDefaultBrowser)
            darwinAppPath
            selectedBrowser.appName
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
          ]
        }
      '';
    })
  ];
}
