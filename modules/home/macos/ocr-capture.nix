{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.macos.ocrCapture;

  ocrSwiftSource = pkgs.writeText "hm-ocr-capture.swift" (builtins.readFile ./ocr_capture.swift);

  ocrCaptureHelper = pkgs.writers.writePython3Bin "hm-ocr-capture" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings
      [ "\"__SWIFT_SOURCE__\"" "\"__CLEANUP_MODE__\"" ]
      [ (builtins.toJSON "${ocrSwiftSource}") (builtins.toJSON cfg.cleanupMode) ]
      (builtins.readFile ./ocr_capture.py)
  );
in
{
  options.macos.ocrCapture = {
    enable = lib.mkEnableOption "macOS OCR screenshot capture and clipboard copy";

    keybinding = lib.mkOption {
      type = lib.types.str;
      default = "cmd-shift-7";
      example = "cmd-shift-7";
      description = "AeroSpace keybinding used to start interactive OCR screen capture.";
    };

    cleanupMode = lib.mkOption {
      type = lib.types.enum [ "balanced" ];
      default = "balanced";
      description = "Text cleanup profile to apply before copying OCR output to the clipboard.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [ (lib.hm.assertions.assertPlatform "macos.ocrCapture" pkgs lib.platforms.darwin) ];

    home.packages = lib.mkIf isDarwin [ ocrCaptureHelper ];

    programs.aerospace.settings.mode.main.binding = lib.mkIf config.programs.aerospace.enable {
      "${cfg.keybinding}" = "exec-and-forget ${lib.getExe ocrCaptureHelper}";
    };
  };
}
