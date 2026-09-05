{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.browserSuite.zen.shopping;
  inherit (config.programs.browserSuite) scrolling;
  inherit (config.programs.browserSuite.shared) profile search;

  browserExtensions =
    config.programs.browserSuite.extensions.shared // config.programs.browserSuite.extensions.zen;
  knownExtensionNames = builtins.attrNames browserExtensions;
  unknownExtensionNames = lib.subtractLists knownExtensionNames cfg.extensions;
  selectedExtensions = lib.filterAttrs (name: _: lib.elem name cfg.extensions) browserExtensions;
  extensionsWithoutPackage = lib.filterAttrs (
    _: extension: extension.package == null
  ) selectedExtensions;

  profileRoot =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/Zen/Profiles"
    else
      "${config.xdg.configHome}/zen";
  profileDirectory = "${profileRoot}/${cfg.profilePath}";
  extensionDirectory = "${profileDirectory}/extensions";
  bootstrapExtension =
    _name: extension:
    let
      destination = "${extensionDirectory}/${extension.id}.xpi";
    in
    ''
      if [[ ! -e ${lib.escapeShellArg destination} ]]; then
        run ${lib.getExe' pkgs.coreutils "install"} -m 0644 \
          ${lib.escapeShellArg extension.package} \
          ${lib.escapeShellArg destination}
      fi
    '';
  bootstrapExtensions = lib.concatStringsSep "\n" (
    lib.mapAttrsToList bootstrapExtension selectedExtensions
  );
  extensionButtonIds = lib.unique (
    lib.optional (browserExtensions ? bitwarden) browserExtensions.bitwarden.id
    ++ map (extension: extension.id) (builtins.attrValues selectedExtensions)
  );
in
{
  options.programs.browserSuite.zen.shopping = {
    enable = lib.mkEnableOption "a separate Zen shopping profile";

    profileName = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9 _-]*";
      default = "Shopping";
      description = "User-visible name of the separate Zen profile.";
    };

    profilePath = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
      default = "shopping";
      description = "Relative Zen profile directory managed for shopping.";
    };

    startUrl = lib.mkOption {
      type = lib.types.strMatching "https://.+";
      description = "HTTPS homepage for shopping sessions.";
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extension names from the shared or Zen-specific catalog to bootstrap
        into this profile. The signed package is copied only when missing so
        Zen can update the installed copy itself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.zen-browser.enable;
        message = "Zen must be enabled when the Zen shopping profile is enabled.";
      }
      {
        assertion = lib.length cfg.extensions == lib.length (lib.unique cfg.extensions);
        message = "The Zen shopping profile contains duplicate extension names.";
      }
      {
        assertion = unknownExtensionNames == [ ];
        message = "Unknown Zen shopping extensions: ${lib.concatStringsSep ", " unknownExtensionNames}";
      }
      {
        assertion = extensionsWithoutPackage == { };
        message = "Every Zen shopping extension must provide a package.";
      }
    ];

    programs.zen-browser.profiles.shopping = {
      id = 1;
      isDefault = false;
      name = cfg.profileName;
      path = cfg.profilePath;
      settings =
        profile.commonSettings
        // profile.scrolling.${scrolling}
        // {
          "browser.contentblocking.category" = "standard";
          "browser.formfill.enable" = false;
          "browser.startup.homepage" = cfg.startUrl;
          "browser.startup.page" = 1;
          "extensions.autoDisableScopes" = 0;
          "extensions.update.autoUpdateDefault" = true;
          "extensions.update.enabled" = true;
          "identity.fxaccounts.enabled" = false;
          "privacy.clearOnShutdown.cache" = true;
          "privacy.clearOnShutdown.cookies" = true;
          "privacy.clearOnShutdown.downloads" = true;
          "privacy.clearOnShutdown.formdata" = true;
          "privacy.clearOnShutdown.history" = true;
          "privacy.clearOnShutdown.offlineApps" = true;
          "privacy.clearOnShutdown.sessions" = true;
          "privacy.clearOnShutdown.siteSettings" = true;
          "privacy.clearOnShutdown_v2.browsingHistoryAndDownloads" = true;
          "privacy.clearOnShutdown_v2.cache" = true;
          "privacy.clearOnShutdown_v2.cookiesAndStorage" = true;
          "privacy.clearOnShutdown_v2.formdata" = true;
          "privacy.clearOnShutdown_v2.siteSettings" = true;
          "privacy.sanitize.sanitizeOnShutdown" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "zen.theme.hide-unified-extensions-button" = false;
          "zen.window-sync.enabled" = true;
          "zen.window-sync.sync-only-pinned-tabs" = true;
          "zen.workspaces.continue-where-left-off" = false;
        };
      search = {
        force = true;
        engines = search.commonEngines;
      };
      extensionButtons."nav-bar" = extensionButtonIds;
      userChrome = ''
        /* Make the transaction-only profile visually distinct. */
        #navigator-toolbox {
          border-top: 4px solid #ff8a00 !important;
        }
      '';
    };

    # Policy can allow an extension only at application scope. Seed a writable
    # signed XPI into this profile once, then leave updates and enablement to Zen.
    home.activation.bootstrapZenShoppingExtensions = lib.mkIf (selectedExtensions != { }) (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${lib.getExe' pkgs.coreutils "mkdir"} -p ${lib.escapeShellArg extensionDirectory}
        ${bootstrapExtensions}
      ''
    );
  };
}
