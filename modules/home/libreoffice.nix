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
    if isDarwin then self.packages.${system}.libreoffice else pkgs.libreoffice-fresh;
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
      path = "/org.openoffice.Office.Common/VCL";
      name = "ForceSkiaRaster";
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
      value = "false";
    }
    {
      path = "/org.openoffice.Office.Recovery/AutoSave";
      name = "TimeIntervall";
      value = "5";
    }
    {
      path = "/org.openoffice.Office.Calc/Formula/Calculation";
      name = "UseThreadedCalculationForFormulaGroups";
      value = "true";
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
  ];

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

  languageToolConfig = pkgs.writeText "languagetool-http-server.properties" ''
    cacheSize=1000
    cacheTTLSeconds=600
    maxCheckThreads=2
    maxWorkQueueSize=20
  '';

  libreofficeWithGrammar = pkgs.replaceVarsWith {
    name = "libreoffice-with-grammar";
    src = ./libreoffice-with-grammar.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      port = toString cfg.languageTool.port;
      stateDir = "${config.xdg.stateHome}/libreoffice";
      mkdirExe = lib.getExe' pkgs.coreutils "mkdir";
      curlExe = lib.getExe pkgs.curl;
      languageToolExe = lib.getExe' pkgs.languagetool "languagetool-http-server";
      inherit languageToolConfig;
      seqExe = lib.getExe' pkgs.coreutils "seq";
      sleepExe = lib.getExe' pkgs.coreutils "sleep";
      settingsPatcherExe = lib.getExe' settingsPatcher "libreoffice-apply-settings";
      libreofficeExe = lib.getExe libreofficePackage;
    };
  };
in
{
  options.programs.libreoffice = {
    enable = lib.mkEnableOption "LibreOffice office suite";

    settings.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply curated modern LibreOffice settings while preserving other profile state.";
    };

    languageTool = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install local LanguageTool integration and the libreoffice-with-grammar launcher.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "Loopback port used by the on-demand LanguageTool HTTP server.";
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
      libreofficePackage
      pkgs.carlito
      pkgs.caladea
      pkgs.liberation_ttf
    ]
    ++ lib.optionals cfg.settings.enable [ settingsPatcher ]
    ++ lib.optionals cfg.languageTool.enable [
      pkgs.languagetool
      libreofficeWithGrammar
    ]
    ++ lib.optionals isLinux [ pkgs.hunspellDicts.en_US-large ];

    home.activation.libreofficeSettings = lib.mkIf cfg.settings.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${settingsPatcher}/bin/libreoffice-apply-settings
      ''
    );
  };
}
