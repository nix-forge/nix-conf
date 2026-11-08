{
  config,
  inputs,

  lib,
  options,
  ...
}:
let
  fixes = import ../../overlays/temporary { inherit inputs lib; };
  cfg = config.macos.preferences;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  user = lib.escapeShellArg config.system.primaryUser;
  privateInstantDefaults = cfg.motion == "instant" && cfg.instantPrivateDefaults;
  spotlightMenuHidden = !cfg.showSpotlightInMenuBar;
  deleteUserDefault = domain: key: ''
    /bin/launchctl asuser "$(/usr/bin/id -u -- ${user})" \
      /usr/bin/sudo --user=${user} -- \
      /usr/bin/defaults delete ${lib.escapeShellArg domain} ${lib.escapeShellArg key} \
      >/dev/null 2>&1 || true
  '';
  readUserDefault = domain: key: ''
    /bin/launchctl asuser "$(/usr/bin/id -u -- ${user})" \
      /usr/bin/sudo --user=${user} -- \
      /usr/bin/defaults read ${lib.escapeShellArg domain} ${lib.escapeShellArg key} \
      2>/dev/null || true
  '';
  readCurrentHostUserDefault = domain: key: ''
    /bin/launchctl asuser "$(/usr/bin/id -u -- ${user})" \
      /usr/bin/sudo --user=${user} -- \
      /usr/bin/defaults -currentHost read ${lib.escapeShellArg domain} ${lib.escapeShellArg key} \
      2>/dev/null || true
  '';
  writeCurrentHostUserBooleanDefault =
    domain: key: value:
    let
      desired = if value then "1" else "0";
      boolValue = if value then "true" else "false";
    in
    (import ../../lib/templates/text.nix) ./scripts/write-current-host-default.sh {
      readCurrentHostUserDefault_domain_key = readCurrentHostUserDefault domain key;
      lib_escapeShellArg_desired = lib.escapeShellArg desired;
      inherit user;
      lib_escapeShellArg_domain = lib.escapeShellArg domain;
      lib_escapeShellArg_key = lib.escapeShellArg key;
      inherit boolValue;
    };
  writeProtectedUserBooleanDefault =
    domain: key: value:
    let
      desired = if value then "1" else "0";
      boolValue = if value then "true" else "false";
    in
    (import ../../lib/templates/text.nix) ./scripts/write-protected-user-default.sh {
      readUserDefault_domain_key = readUserDefault domain key;
      lib_escapeShellArg_desired = lib.escapeShellArg desired;
      inherit domain;
      inherit key;
      inherit user;
      lib_escapeShellArg_domain = lib.escapeShellArg domain;
      lib_escapeShellArg_key = lib.escapeShellArg key;
      inherit boolValue;
    };

  obsoleteDefaults = [
    [
      "com.apple.SoftwareUpdate"
      "AutomaticCheckEnabled"
    ]
    [
      "com.apple.SoftwareUpdate"
      "ScheduleFrequency"
    ]
    [
      "com.apple.SoftwareUpdate"
      "AutomaticDownload"
    ]
    [
      "com.apple.SoftwareUpdate"
      "CriticalUpdateInstall"
    ]
    [
      "com.apple.SoftwareUpdate"
      "AutomaticallyInstallMacOSUpdates"
    ]
    [
      "com.apple.Safari"
      "IncludeInternalDebugMenu"
    ]
    [
      "com.apple.Safari"
      "UniversalSearchEnabled"
    ]
    [
      "com.apple.Safari"
      "SuppressSearchSuggestions"
    ]
    [
      "com.apple.Safari"
      "DebugSnapshotsUpdatePolicy"
    ]
    [
      "com.apple.Safari"
      "FindOnPageMatchesWordStartsOnly"
    ]
    [
      "com.apple.Safari"
      "ProxiesInBookmarksBar"
    ]
    [
      "com.apple.Mail"
      "AddressesIncludeNameOnPasteboard"
    ]
    [
      "com.apple.Mail"
      "DisableReplyAnimations"
    ]
    [
      "com.apple.Mail"
      "DisableSendAnimations"
    ]
    [
      "com.apple.terminal"
      "StringEncodings"
    ]
    [
      "com.apple.finder"
      "OpenWindowForNewRemovableDisk"
    ]
    [
      "com.apple.finder"
      "QLEnableTextSelection"
    ]
    [
      "com.apple.finder"
      "SidebarDevicesSectionDisclosedState"
    ]
    [
      "com.apple.finder"
      "SidebarPlacesSectionDisclosedState"
    ]
    [
      "com.apple.AppleMultitouchTrackpad"
      "TrackpadCornerSecondaryClick"
    ]
    [
      "com.apple.driver.AppleBluetoothMultitouch.trackpad"
      "TrackpadCornerSecondaryClick"
    ]
  ];
  inactiveDefaults =
    lib.optionals (cfg.motion != "instant") [
      [
        "-g"
        "NSAutomaticWindowAnimationsEnabled"
      ]
      [
        "-g"
        "NSWindowResizeTime"
      ]
      [
        "-g"
        "NSScrollAnimationEnabled"
      ]
      [
        "-g"
        "NSUseAnimatedFocusRing"
      ]
      [
        "com.apple.dock"
        "expose-animation-duration"
      ]
      [
        "com.apple.dock"
        "autohide-time-modifier"
      ]
      [
        "com.apple.dock"
        "autohide-delay"
      ]
      [
        "com.apple.dock"
        "launchanim"
      ]
      [
        "com.apple.dock"
        "slow-motion-allowed"
      ]
    ]
    ++ lib.optionals (cfg.motion == "normal") [
      [
        "com.apple.universalaccess"
        "reduceMotion"
      ]
    ]
    ++ lib.optionals (!privateInstantDefaults) [
      [
        "com.apple.finder"
        "DisableAllAnimations"
      ]
      [
        "com.apple.dock"
        "springboard-show-duration"
      ]
      [
        "com.apple.dock"
        "springboard-hide-duration"
      ]
      [
        "com.apple.dock"
        "springboard-page-duration"
      ]
    ]
    ++ lib.optionals (!cfg.fontSmoothing) [
      [
        "-g"
        "AppleFontSmoothing"
      ]
    ];
  defaultsToDelete = (lib.optionals cfg.cleanupLegacyDefaults obsoleteDefaults) ++ inactiveDefaults;
in
{
  imports = [ (fixes.apply "darwin-app-management-consent" inputs.nix-darwin) ];

  options.macos.preferences = {
    enable = mkEnableOption "opinionated, typed macOS preferences" // {
      default = true;
    };

    motion = mkOption {
      type = types.enum [
        "normal"
        "reduced"
        "instant"
      ];
      default = "reduced";
      description = ''
        Animation policy. Reduced uses Apple's accessibility setting. Instant
        also changes typed animation-duration defaults and may need review after
        a major macOS update.
      '';
    };

    instantPrivateDefaults = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether the instant profile also writes version-sensitive Finder and
        app-launcher animation defaults observed in current macOS binaries.
      '';
    };

    reduceTransparency = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to use Apple's Reduce Transparency setting.";
    };

    fontSmoothing = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to retain the legacy AppleFontSmoothing value.";
    };

    showHiddenFiles = mkOption {
      type = types.bool;
      default = true;
      description = "Whether Finder shows dotfiles and other hidden files.";
    };

    showDesktopIcons = mkOption {
      type = types.bool;
      default = false;
      description = "Whether Finder draws file icons on the desktop.";
    };

    showBatteryPercentage = mkOption {
      type = types.bool;
      default = true;
      description = "Whether Control Center shows the battery percentage.";
    };

    showSiriInMenuBar = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the menu bar shows the Siri icon.";
    };

    showPasswordsInMenuBar = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the Passwords app provides a menu bar item.";
    };

    showSpotlightInMenuBar = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the menu bar shows the Spotlight icon.";
    };

    screenshotDirectory = mkOption {
      type = types.strMatching "^/.*";
      default = "${config.users.users.${config.system.primaryUser}.home}/Pictures/Screenshots";
      description = "Absolute directory used by the macOS screenshot tools.";
    };

    safari = {
      enableDeveloperMenu = mkOption {
        type = types.bool;
        default = true;
        description = "Whether Safari exposes its supported developer menu.";
      };

      openSafeDownloads = mkOption {
        type = types.bool;
        default = false;
        description = "Whether Safari automatically opens files it labels safe.";
      };
    };

    cleanupLegacyDefaults = mkOption {
      type = types.bool;
      default = true;
      description = "Delete obsolete preferences previously written by the Home Manager module.";
    };

    customUserPreferences = mkOption {
      type = options.system.defaults.CustomUserPreferences.type;
      default = { };
      description = "Extra per-user defaults for settings without typed nix-darwin options.";
    };

    customSystemPreferences = mkOption {
      type = options.system.defaults.CustomSystemPreferences.type;
      default = { };
      description = "Extra machine defaults for settings without typed nix-darwin options.";
    };
  };

  config = mkIf cfg.enable {
    system.defaults = {
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = lib.mkDefault true;

      NSGlobalDomain = {
        AppleKeyboardUIMode = lib.mkDefault 2;
        ApplePressAndHoldEnabled = lib.mkDefault false;
        AppleShowAllExtensions = lib.mkDefault true;
        AppleShowAllFiles = lib.mkDefault cfg.showHiddenFiles;
        InitialKeyRepeat = lib.mkDefault 20;
        KeyRepeat = lib.mkDefault 2;
        NSAutomaticCapitalizationEnabled = lib.mkDefault false;
        NSAutomaticDashSubstitutionEnabled = lib.mkDefault false;
        NSAutomaticInlinePredictionEnabled = lib.mkDefault false;
        NSAutomaticPeriodSubstitutionEnabled = lib.mkDefault false;
        NSAutomaticQuoteSubstitutionEnabled = lib.mkDefault false;
        NSAutomaticSpellingCorrectionEnabled = lib.mkDefault false;
        NSNavPanelExpandedStateForSaveMode = lib.mkDefault true;
        NSNavPanelExpandedStateForSaveMode2 = lib.mkDefault true;
        PMPrintingExpandedStateForPrint = lib.mkDefault true;
        PMPrintingExpandedStateForPrint2 = lib.mkDefault true;
        "com.apple.swipescrolldirection" = lib.mkDefault true;
      }
      // lib.optionalAttrs cfg.fontSmoothing { AppleFontSmoothing = lib.mkDefault 2; }
      // lib.optionalAttrs (cfg.motion == "instant") {
        NSAutomaticWindowAnimationsEnabled = lib.mkDefault false;
        NSScrollAnimationEnabled = lib.mkDefault false;
        NSUseAnimatedFocusRing = lib.mkDefault false;
        NSWindowResizeTime = lib.mkDefault 0.001;
      };

      dock = {
        autohide = lib.mkDefault true;
        enable-spring-load-actions-on-all-items = lib.mkDefault true;
        expose-group-apps = lib.mkDefault true;
        magnification = lib.mkDefault false;
        mineffect = lib.mkDefault "scale";
        minimize-to-application = lib.mkDefault true;
        mouse-over-hilite-stack = lib.mkDefault true;
        mru-spaces = lib.mkDefault false;
        orientation = lib.mkDefault "bottom";
        show-process-indicators = lib.mkDefault true;
        show-recents = lib.mkDefault false;
        showhidden = lib.mkDefault true;
        static-only = lib.mkDefault false;
        tilesize = lib.mkDefault 48;
        wvous-tl-corner = lib.mkDefault 1;
        wvous-tr-corner = lib.mkDefault 1;
        wvous-bl-corner = lib.mkDefault 1;
        wvous-br-corner = lib.mkDefault 1;
      }
      // lib.optionalAttrs (cfg.motion == "instant") {
        autohide-delay = lib.mkDefault 0.0;
        autohide-time-modifier = lib.mkDefault 0.0;
        expose-animation-duration = lib.mkDefault 0.0;
        launchanim = lib.mkDefault false;
        slow-motion-allowed = lib.mkDefault false;
      };

      finder = {
        AppleShowAllExtensions = lib.mkDefault true;
        AppleShowAllFiles = lib.mkDefault cfg.showHiddenFiles;
        CreateDesktop = lib.mkDefault cfg.showDesktopIcons;
        FXDefaultSearchScope = lib.mkDefault "SCcf";
        FXEnableExtensionChangeWarning = lib.mkDefault true;
        FXPreferredViewStyle = lib.mkDefault "Nlsv";
        FXRemoveOldTrashItems = lib.mkDefault true;
        QuitMenuItem = lib.mkDefault true;
        ShowPathbar = lib.mkDefault true;
        ShowStatusBar = lib.mkDefault true;
        _FXShowPosixPathInTitle = lib.mkDefault true;
        _FXSortFoldersFirst = lib.mkDefault true;
      };

      trackpad = {
        Clicking = lib.mkDefault true;
        Dragging = lib.mkDefault false;
        TrackpadCornerSecondaryClick = lib.mkDefault 0;
        TrackpadRightClick = lib.mkDefault true;
        TrackpadThreeFingerDrag = lib.mkDefault false;
      };

      screencapture = {
        disable-shadow = lib.mkDefault true;
        location = lib.mkDefault cfg.screenshotDirectory;
        save-selections = lib.mkDefault true;
        show-thumbnail = lib.mkDefault true;
        target = lib.mkDefault "file";
        type = lib.mkDefault "png";
      };

      screensaver = {
        askForPassword = lib.mkDefault true;
        askForPasswordDelay = lib.mkDefault 0;
      };

      controlcenter.BatteryShowPercentage = lib.mkDefault cfg.showBatteryPercentage;

      CustomUserPreferences = lib.recursiveUpdate (
        {
          "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
          "com.apple.Passwords".EnableMenuBarExtra = cfg.showPasswordsInMenuBar;
          "com.apple.Siri".StatusMenuVisible = cfg.showSiriInMenuBar;
          "com.apple.desktopservices" = {
            DSDontWriteNetworkStores = true;
            DSDontWriteUSBStores = true;
          };
        }
        // lib.optionalAttrs privateInstantDefaults {
          "com.apple.finder".DisableAllAnimations = true;
          "com.apple.dock" = {
            springboard-show-duration = 0.0;
            springboard-hide-duration = 0.0;
            springboard-page-duration = 0.0;
          };
        }
      ) cfg.customUserPreferences;

      CustomSystemPreferences = cfg.customSystemPreferences;
    };

    system.activationScripts.userDefaults.text = lib.mkMerge [
      (lib.mkBefore (
        (import ../../lib/templates/text.nix) ./scripts/snapshot-user-defaults.sh {
          readUserDefault_com_apple_finder_DisableAllAnimations = readUserDefault "com.apple.finder" "DisableAllAnimations";
          readUserDefault_com_apple_Passwords_EnableMenuBarExtra = readUserDefault "com.apple.Passwords" "EnableMenuBarExtra";
          readUserDefault_com_apple_Siri_StatusMenuVisible = readUserDefault "com.apple.Siri" "StatusMenuVisible";
          readCurrentHostUserDefault_com_apple_Spotlight_MenuItemHidde = readCurrentHostUserDefault "com.apple.Spotlight" "MenuItemHidden";
        }
      ))
      (lib.mkBefore ''
        ${writeCurrentHostUserBooleanDefault "com.apple.Spotlight" "MenuItemHidden" spotlightMenuHidden}
        ${writeProtectedUserBooleanDefault "com.apple.universalaccess" "reduceTransparency"
          cfg.reduceTransparency
        }
        ${lib.optionalString (cfg.motion != "normal") (
          writeProtectedUserBooleanDefault "com.apple.universalaccess" "reduceMotion" true
        )}
        ${writeProtectedUserBooleanDefault "com.apple.Safari" "AutoOpenSafeDownloads"
          cfg.safari.openSafeDownloads
        }
        ${writeProtectedUserBooleanDefault "com.apple.Safari" "IncludeDevelopMenu"
          cfg.safari.enableDeveloperMenu
        }
      '')
      (lib.mkBefore (
        (import ../../lib/templates/text.nix) ./scripts/remove-obsolete-user-defaults.sh {
          lib_concatMapStringsSep_n_entry_deleteUserDefault_builtins_e = lib.concatMapStringsSep "\n" (
            entry: deleteUserDefault (builtins.elemAt entry 0) (builtins.elemAt entry 1)
          ) defaultsToDelete;
        }
      ))
      (lib.mkAfter (
        (import ../../lib/templates/text.nix) ./scripts/restart-changed-desktop-services.sh {
          readUserDefault_com_apple_finder_DisableAllAnimations = readUserDefault "com.apple.finder" "DisableAllAnimations";
          inherit user;
          readUserDefault_com_apple_Siri_StatusMenuVisible = readUserDefault "com.apple.Siri" "StatusMenuVisible";
          readCurrentHostUserDefault_com_apple_Spotlight_MenuItemHidde = readCurrentHostUserDefault "com.apple.Spotlight" "MenuItemHidden";
          readUserDefault_com_apple_Passwords_EnableMenuBarExtra = readUserDefault "com.apple.Passwords" "EnableMenuBarExtra";
        }
      ))
    ];
  };
}
