{
  config,
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  cfg = config.programs.libreoffice;
  libreofficePackage =
    if isDarwin then self.packages.${system}.libreoffice else pkgs.libreoffice-stable;
  profileDir =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/LibreOffice/4/user"
    else
      "${config.xdg.configHome}/libreoffice/4/user";
  registryFile = "${profileDir}/registrymodifications.xcu";
  languageToolUrl = "http://127.0.0.1:${toString cfg.languageTool.port}/v2";

  managedSettings = [
    {
      path = "/org.openoffice.Office.Common/VCL";
      name = "UseSkia";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/VCL";
      name = "ForceSkia";
      value = "false";
    }
    {
      path = "/org.openoffice.Office.Common/Drawinglayer";
      name = "AntiAliasing";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Canvas";
      name = "UseAntialiasingCanvas";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/View/FontAntiAliasing";
      name = "Enabled";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Writer/Layout/Window";
      name = "SmoothScroll";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.WriterWeb/Layout/Window";
      name = "SmoothScroll";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Appearance";
      name = "ApplicationAppearance";
      value = "0";
    }
    {
      path = "/org.openoffice.Office.Common/Misc";
      name = "UseSystemFileDialog";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Misc";
      name = "UseSystemColorDialog";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Misc";
      name = "UseSystemPrintDialog";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Save/Document";
      name = "CreateBackup";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Save/Document";
      name = "BackupIntoDocumentFolder";
      value = "false";
    }
    {
      path = "/org.openoffice.Office.Common/Save/Document";
      name = "WarnAlienFormat";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Recovery/RecoveryInfo";
      name = "Enabled";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Recovery/AutoSave";
      name = "Enabled";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Recovery/AutoSave";
      name = "UserAutoSaveEnabled";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Recovery/AutoSave";
      # The upstream key is intentionally spelled ``TimeInterval``.
      # ``TimeInterval`` is silently ignored by LibreOffice.
      name = "TimeInterval";
      value = "5";
    }
    {
      path = "/org.openoffice.Office.Calc/Formula/Calculation";
      name = "UseThreadedCalculationForFormulaGroups";
      value = "true";
    }
    {
      # Ask before parsing uncommon legacy formats instead of automatically
      # handing potentially hostile input to an importer.
      path = "/org.openoffice.Office.Common/Security";
      name = "LoadExoticFileFormats";
      value = "1";
    }
    {
      # High means macros must be from a trusted location or signed by a
      # trusted author. It preserves normal macro workflows without accepting
      # unsigned document macros.
      path = "/org.openoffice.Office.Common/Security/Scripting";
      name = "MacroSecurityLevel";
      value = "2";
    }
    {
      path = "/org.openoffice.Office.Common/Security/Scripting";
      name = "BlockUntrustedRefererLinks";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Security/Scripting";
      name = "HyperlinksWithCtrlClick";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Security/Scripting";
      name = "WarnSaveOrSendDoc";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Security/Scripting";
      name = "WarnPrintDoc";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Common/Security/Scripting";
      name = "WarnCreatePDF";
      value = "true";
    }
    {
      # Loading external spreadsheet links only when requested avoids surprise
      # network/file reads while keeping the feature available.
      path = "/org.openoffice.Office.Calc/Content/Update";
      name = "Link";
      value = "2";
    }
  ]
  ++
    map
      (application: {
        path = "/org.openoffice.Office.UI.ToolbarMode/Applications/${application}";
        name = "Active";
        value = "Tabbed";
      })
      [
        "Writer"
        "Calc"
        "Impress"
        "Draw"
      ]
  ++ lib.optionals cfg.languageTool.enable [
    {
      path = "/org.openoffice.Office.Linguistic/GrammarChecking/LanguageTool";
      name = "BaseURL";
      value = languageToolUrl;
    }
    {
      path = "/org.openoffice.Office.Linguistic/GrammarChecking/LanguageTool";
      name = "IsEnabled";
      value = "true";
    }
    {
      path = "/org.openoffice.Office.Linguistic/GrammarChecking/LanguageTool";
      name = "RestProtocol";
      value = "";
    }
  ]
  ++ cfg.settings.extra;

  settingsJson = pkgs.writeText "libreoffice-managed-settings.json" (builtins.toJSON managedSettings);

  settingsPatcherPython = pkgs.replaceVarsWith {
    name = "libreoffice-apply-settings.py";
    src = ./libreoffice-apply-settings.py;
    replacements = { };
  };

  settingsPatcher = pkgs.replaceVarsWith {
    name = "libreoffice-apply-settings";
    src = ./libreoffice-apply-settings.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      profile = registryFile;
      pgrepExe = if isDarwin then "/usr/bin/pgrep" else lib.getExe' pkgs.procps "pgrep";
      pythonExe = lib.getExe pkgs.python3;
      inherit settingsJson settingsPatcherPython;
    };
  };

  languageToolConfig = pkgs.replaceVarsWith {
    name = "languagetool-http-server.properties";
    src = ./languagetool-http-server.properties.in;
    replacements = {
      cacheSize = toString cfg.languageTool.cacheSize;
      cacheTTLSeconds = toString cfg.languageTool.cacheTTLSeconds;
      maxCheckThreads = toString cfg.languageTool.maxCheckThreads;
      maxWorkQueueSize = toString cfg.languageTool.maxWorkQueueSize;
    };
  };
  languageToolStateDir = "${config.xdg.stateHome}/libreoffice/languagetool";
  languageToolLogDir = "${languageToolStateDir}/logs";
  languageToolCommand = [
    (lib.getExe' pkgs.languagetool "languagetool-http-server")
    "--config"
    "${languageToolConfig}"
    "--port"
    (toString cfg.languageTool.port)
    # The embedded server is strictly local. Do not pass --public.
    "--notLogIP"
  ];
in
{
  options.programs.libreoffice = {
    enable = lib.mkEnableOption "LibreOffice office suite";

    package = lib.mkOption {
      type = lib.types.package;
      default = libreofficePackage;
      defaultText = lib.literalExpression "if pkgs.stdenv.hostPlatform.isDarwin then self.packages.\${system}.libreoffice else pkgs.libreoffice-stable";
      description = "LibreOffice package to install.";
    };

    settings.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply curated modern LibreOffice settings while preserving other profile state.";
    };

    settings.extra = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption { type = lib.types.str; };
            name = lib.mkOption { type = lib.types.str; };
            value = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      example = lib.literalExpression ''
        [ {
          path = "/org.openoffice.Office.Common/Save/Document";
          name = "OFDefaultVersion";
          value = "4";
        } ]
      '';
      description = ''
        Additional registry values to manage. Entries are applied after the
        curated defaults, so they can deliberately override one of them.
      '';
    };

    languageTool = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install and start a local, loopback-only LanguageTool grammar checker.";
      };

      appArmorProfile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "nixos-languagetool";
        description = ''
          Name of an already-loaded AppArmor profile to apply only to the
          LanguageTool user service. Leave this null unless the host declares
          and tests the matching policy.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "Loopback port used by the local LanguageTool HTTP server.";
      };

      cacheSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1000;
        description = "Maximum number of LanguageTool results held in memory.";
      };

      cacheTTLSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "How long LanguageTool results remain cached in seconds.";
      };

      maxCheckThreads = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = "Maximum concurrent local grammar-checking workers.";
      };

      maxWorkQueueSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 40;
        description = "Maximum queued local grammar-checking requests.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin || isLinux;
        message = "programs.libreoffice only supports Linux and Darwin Home Manager hosts.";
      }
    ];

    home.packages = [
      cfg.package
      pkgs.carlito
      pkgs.caladea
      pkgs.liberation_ttf
    ]
    ++ lib.optionals cfg.settings.enable [ settingsPatcher ]
    ++ lib.optionals cfg.languageTool.enable [
      pkgs.languagetool
      pkgs.hunspellDicts.en_US-large
    ];

    home.activation = {
      libreofficeSettings = lib.mkIf cfg.settings.enable (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${settingsPatcher}/bin/libreoffice-apply-settings
        ''
      );

      libreofficeLanguageToolState = lib.mkIf cfg.languageTool.enable (
        lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
          run ${lib.getExe' pkgs.coreutils "mkdir"} -m 700 -p ${lib.escapeShellArg languageToolLogDir}
        ''
      );
    };

    systemd.user.services.libreoffice-languagetool = lib.mkIf (isLinux && cfg.languageTool.enable) {
      Unit = {
        Description = "LibreOffice local LanguageTool grammar checker";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.escapeShellArgs languageToolCommand;
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        LockPersonality = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0077";

        # LanguageTool runs a JVM, which legitimately uses writable executable
        # mappings for JIT compilation.  Do not set MemoryDenyWriteExecute
        # without a separate JVM-specific validation.  The server is accessed
        # over the user's loopback namespace, so a user-service IP filter is
        # likewise intentionally deferred rather than risking LibreOffice
        # integration.
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      }
      // lib.optionalAttrs (cfg.languageTool.appArmorProfile != null) {
        AppArmorProfile = cfg.languageTool.appArmorProfile;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    launchd.agents.libreoffice-languagetool = lib.mkIf (isDarwin && cfg.languageTool.enable) {
      enable = true;
      domain = "gui";
      config = {
        Label = "org.libreoffice.languagetool";
        ProgramArguments = languageToolCommand;
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ProcessType = "Background";
        ThrottleInterval = 5;
        Umask = 63;
        StandardOutPath = "${languageToolLogDir}/server.out.log";
        StandardErrorPath = "${languageToolLogDir}/server.err.log";
      };
    };
  };
}
