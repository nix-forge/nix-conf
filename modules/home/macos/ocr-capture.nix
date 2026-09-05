{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  cfg = config.macos.ocrCapture;
  appPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/OCR Capture.app";
  executablePath = "${appPath}/Contents/MacOS/hm-ocr-capture";

  arguments = [
    "capture"
    "--recognition"
    cfg.recognitionMode
    "--backend"
    cfg.recognitionBackend
    "--render"
    cfg.renderMode
    "--max-pixels"
    (toString cfg.maximumPixels)
    "--timeout"
    (toString cfg.timeoutSeconds)
    "--candidates"
    (toString cfg.maximumCandidates)
    "--minimum-text-height"
    (toString cfg.minimumTextHeight)
  ]
  ++ lib.optionals (!cfg.languageCorrection) [ "--no-language-correction" ]
  ++ lib.optionals cfg.smallText [ "--small-text" ]
  ++ lib.concatMap (language: [
    "--language"
    language
  ]) cfg.languages
  ++ lib.concatMap (word: [
    "--custom-word"
    word
  ]) cfg.customWords;

  launchCommand = lib.concatMapStringsSep " " lib.escapeShellArg ([ executablePath ] ++ arguments);
in
{
  options.macos.ocrCapture = {
    enable = lib.mkEnableOption "native macOS region-screenshot OCR";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ocr-capture;
      defaultText = lib.literalExpression "pkgs.ocr-capture";
      description = "Swift OCR Capture application package to install.";
    };

    shortcuts.copyRegion = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = "cmd-shift-7";
      description = "AeroSpace shortcut that uses the macOS region selector and copies its text.";
    };

    recognitionMode = lib.mkOption {
      type = lib.types.enum [
        "accurate"
        "fast"
        "adaptive"
      ];
      default = "accurate";
      description = "Vision quality policy. Adaptive retries low-confidence fast results accurately.";
    };

    recognitionBackend = lib.mkOption {
      type = lib.types.enum [
        "automatic"
        "legacy"
        "document"
      ];
      default = "automatic";
      description = ''
        OCR backend policy. Automatic uses structured document recognition on
        supported macOS 26 builds and falls back to legacy Vision text OCR.
      '';
    };

    renderMode = lib.mkOption {
      type = lib.types.enum [
        "raw"
        "lines"
        "paragraph"
        "code"
        "table"
        "markdown"
      ];
      default = "lines";
      description = "How structured Vision observations are rendered for the clipboard.";
    };

    languages = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      example = [ "en-US" ];
      description = "Preferred Vision languages, or an empty list for automatic detection.";
    };

    customWords = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      example = [
        "NixOS"
        "Home Manager"
      ];
      description = "Vocabulary hints supplied to Vision recognition.";
    };

    languageCorrection = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether Vision applies language-aware corrections.";
    };

    smallText = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the bounded high-quality small-text preprocessing preset.";
    };

    minimumTextHeight = lib.mkOption {
      type = lib.types.numbers.between 0 1;
      default = 0;
      description = "Minimum text height as a fraction of the image; larger values reduce work.";
    };

    maximumPixels = lib.mkOption {
      type = lib.types.ints.between 1000000 100000000;
      default = 24000000;
      description = "Maximum number of pixels sent to Vision after adaptive resizing.";
    };

    timeoutSeconds = lib.mkOption {
      type = lib.types.numbers.between 1 120;
      default = 20;
      description = "Recognition timeout in seconds.";
    };

    maximumCandidates = lib.mkOption {
      type = lib.types.ints.between 1 10;
      default = 3;
      description = "Number of Vision text candidates retained per observation.";
    };

    signingIdentity = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "Apple Development: Developer Name (TEAMID)";
      description = ''
        Optional locally installed Apple code-signing identity used to re-sign
        the copied application. The private key remains in Keychain and never
        enters the Nix store. Null retains the reproducible ad-hoc signature.
      '';
    };

    applicationPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = appPath;
      description = "Stable copied application path used for launch and TCC identity.";
    };

    engine = lib.mkOption {
      type = lib.types.enum [ "native" ];
      default = "native";
      readOnly = true;
      description = "Resolved all-Swift OCR implementation, exposed for diagnostics.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "macos.ocrCapture" pkgs lib.platforms.darwin)
      {
        assertion = !isDarwin || config.targets.darwin.copyApps.enable;
        message = "macos.ocrCapture requires targets.darwin.copyApps.enable for a stable TCC identity.";
      }
    ];

    warnings = lib.optional (isDarwin && cfg.signingIdentity == null) ''
      macos.ocrCapture uses a reproducible ad-hoc signature. Screen Recording
      permission may need approval again after an application update. Set
      macos.ocrCapture.signingIdentity to a local Apple signing identity for
      the most stable designated requirement.
    '';

    home.packages = lib.mkIf isDarwin [ cfg.package ];

    targets.darwin = lib.mkIf isDarwin {
      copyApps.enable = lib.mkDefault true;
      linkApps.enable = lib.mkDefault false;
    };

    home.activation.signCopiedOCRCapture = lib.mkIf (isDarwin && cfg.signingIdentity != null) (
      lib.hm.dag.entryAfter [ "copyApps" ] ''
        app=${lib.escapeShellArg appPath}
        identity=${lib.escapeShellArg cfg.signingIdentity}
        run /bin/wait4path "$app"
        if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$identity"; then
          printf 'OCR Capture signing identity is unavailable: %s\n' "$identity" >&2
          exit 1
        fi
        run /usr/bin/codesign --force --options runtime --sign "$identity" "$app"
        run /usr/bin/codesign --verify --strict --verbose=2 "$app"
      ''
    );

    programs.aerospace.settings.mode.main.binding = lib.mkIf (
      config.programs.aerospace.enable && cfg.shortcuts.copyRegion != null
    ) { ${cfg.shortcuts.copyRegion} = "exec-and-forget ${launchCommand}"; };
  };
}
