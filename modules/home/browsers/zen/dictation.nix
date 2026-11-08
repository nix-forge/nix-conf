{
  config,
  lib,
  myLib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.programs.zenSearchDictation;
  hyprlandPackage = myLib.desktop.resolveHyprlandPackage { inherit config pkgs osConfig; };
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  defaultModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/ggml-small.en-q5_1.bin";
    hash = "sha256-v9/0iU3Ldrv2R9ViY+oqlmRUI/FmkXb0hEob+OR4rTA=";
  };
  command = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "zen-dictate";
    src = ./scripts/zen-dictate-linux.sh.in;
    dir = "bin";
    runtimeInputs =
      with pkgs;
      [
        coreutils
        libnotify
        pipewire
        util-linux
        whisper-cpp
      ]
      ++ lib.optionals (cfg.linux.delivery == "review-dialog") [ pkgs.zenity ]
      ++ lib.optionals (cfg.linux.delivery == "hyprland-urlbar") [
        hyprlandPackage
        pkgs.jq
        pkgs.wtype
      ];
    replacements = {
      model = lib.escapeShellArg (toString cfg.model);
      language = lib.escapeShellArg cfg.language;
      recordingSeconds = toString cfg.maxRecordingSeconds;
      sampleCount = toString (cfg.maxRecordingSeconds * 16000);
      delivery = cfg.linux.delivery;
      zenExe = lib.getExe config.programs.zen-browser.package;
    };
  };
  bind = key: action: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON "${lib.getExe' command "zen-dictate"} ${action}"})")
    ];
  };
in
{
  options.programs.zenSearchDictation = {
    enable = lib.mkEnableOption "Zen search dictation";

    model = lib.mkOption {
      type = lib.types.path;
      default = defaultModel;
      description = "Whisper GGML model file. Select a multilingual model for languages other than English.";
    };
    language = lib.mkOption {
      type = lib.types.str;
      default = "en";
      description = "Whisper language code, or auto for language detection with a multilingual model.";
    };
    maxRecordingSeconds = lib.mkOption {
      type = lib.types.ints.between 1 600;
      default = 60;
      description = "Maximum recording duration. The sample count and process deadline use this same limit.";
    };

    linux.delivery = lib.mkOption {
      type = lib.types.enum [
        "review-dialog"
        "hyprland-urlbar"
      ];
      default = "review-dialog";
      description = ''
        Review the transcript in a desktop dialog before searching, or enter
        it into the focused Zen address bar on Hyprland without submitting.
      '';
    };

    linux.hyprlandShortcut = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Bind Super+Alt+D to toggle and Super+Alt+Shift+D to cancel on Hyprland.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "programs.zenSearchDictation currently supports Linux; use native macOS Dictation on Darwin.";
      }
      {
        assertion = cfg.language == "en" || toString cfg.model != toString defaultModel;
        message = "Non-English dictation requires a multilingual programs.zenSearchDictation.model.";
      }
      {
        assertion = cfg.language != "";
        message = "programs.zenSearchDictation.language must not be empty.";
      }
      {
        assertion = config.programs.zen-browser.enable;
        message = "programs.zenSearchDictation requires Zen Browser.";
      }
      {
        assertion =
          !isLinux
          || (cfg.linux.delivery != "hyprland-urlbar" && !cfg.linux.hyprlandShortcut)
          || config.wayland.windowManager.hyprland.enable;
        message = "The Hyprland Zen dictation delivery and shortcut require Hyprland.";
      }
    ];

    home.packages = lib.optionals isLinux [ command ];

    wayland.windowManager.hyprland.settings.bind = lib.mkIf (isLinux && cfg.linux.hyprlandShortcut) (
      lib.mkAfter [
        (bind "SUPER + ALT + D" "toggle")
        (bind "SUPER + ALT + SHIFT + D" "cancel")
      ]
    );
  };
}
