{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.programs.voiceDictation;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  dataDir =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/com.pais.handy"
    else
      "${config.xdg.dataHome}/com.pais.handy";
  # Handy v0.9.6's catalog pins this archive by SHA-256. English Parakeet V2
  # offers high-quality recognition without a second local cleanup model.
  archive = pkgs.fetchurl {
    url = "https://blob.handy.computer/parakeet-v2-int8.tar.gz";
    sha256 = "ac9b9429984dd565b25097337a887bb7f0f8ac393573661c651f0e7d31563991";
  };
  model = pkgs.runCommand "dictation-parakeet-v2-int8" { } ''
    mkdir -p "$out"
    tar --warning=no-unknown-keyword -xzf ${archive} -C "$out" --strip-components=1 --exclude='._*'
    test -f "$out/encoder-model.int8.onnx"
    test -f "$out/vocab.txt"
    test -f "$out/decoder_joint-model.int8.onnx"
  '';
  shortcutKeys = {
    toggle = [
      "CTRL"
      "ALT"
      "D"
    ];
    cancel = [
      "CTRL"
      "ALT"
      "SHIFT"
      "D"
    ];
  };
  linuxChords = lib.mapAttrs (_: keys: lib.concatStringsSep " + " keys) shortcutKeys;
  macChords = lib.mapAttrs (
    _: keys:
    lib.concatStringsSep "+" (map (key: if key == "ALT" then "option" else lib.toLower key) keys)
  ) shortcutKeys;
  actions = {
    toggle = "record toggle";
    cancel = "record cancel";
  };
  shortcutLua = lib.concatMapStringsSep "\n" (action: ''
    hl.unbind(${builtins.toJSON linuxChords.${action}})
    hl.bind(${
      builtins.toJSON linuxChords.${action}
    }, hl.dsp.exec_cmd(${builtins.toJSON "${lib.getExe cfg.package} ${actions.${action}}"}))
  '') (builtins.attrNames shortcutKeys);
  binding = id: chord: {
    inherit id;
    name = id;
    description = "Local voice dictation";
    default_binding = chord;
    current_binding = chord;
  };
  preferences = (pkgs.formats.json { }).generate "handy-preferences.json" {
    selected_model = "parakeet-tdt-0.6b-v2";
    model_unload_timeout = "immediately";
    always_on_microphone = false;
    push_to_talk = false;
    audio_feedback = true;
    audio_feedback_volume = 0.4;
    start_hidden = true;
    autostart_enabled = false; # The native service manager owns its lifetime.
    update_checks_enabled = false; # Nix owns updates.
    post_process_enabled = false;
    auto_submit = false;
    paste_method = "ctrl_v";
    clipboard_handling = "dont_modify";
    selected_language = "en";
    translate_to_english = false;
    recording_retention_period = "never";
    log_level = "warn";
    bindings = {
      transcribe = binding "transcribe" macChords.toggle;
      transcribe_with_post_process = binding "transcribe_with_post_process" "";
      cancel = binding "cancel" macChords.cancel;
    };
  };
  reconciler = pkgs.writers.writePython3Bin "configure-voice-dictation" {
    flakeIgnore = [ "E501" ];
  } ./dictation-assets/configure.py;
  prepare = pkgs.writeShellApplication {
    name = "prepare-voice-dictation";
    text = ''
      exec ${lib.getExe reconciler} --data-dir ${lib.escapeShellArg dataDir} \
        --preferences ${preferences} --model ${model}
    '';
  };
  launcher =
    if isDarwin then
      "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Handy.app/Contents/MacOS/handy"
    else
      lib.getExe cfg.package;
  start = pkgs.writeShellApplication {
    name = "start-voice-dictation";
    text = ''
      ${lib.getExe prepare}
      exec ${lib.escapeShellArg launcher} --start-hidden
    '';
  };
  hyprlandPackage =
    if osConfig != null && (osConfig.programs.hyprland.enable or false) then
      osConfig.programs.hyprland.package
    else if config.wayland.windowManager.hyprland.package != null then
      config.wayland.windowManager.hyprland.package
    else
      pkgs.hyprland;
  registerBindings = pkgs.writeShellApplication {
    name = "register-dictation-shortcuts";
    text = ''
      exec ${lib.getExe' hyprlandPackage "hyprctl"} eval ${lib.escapeShellArg shortcutLua}
    '';
  };
  bind = key: argument: {
    _args = [
      key
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON "${launcher} ${argument}"})")
    ];
  };
in
{
  imports = [ ../macos/application-capabilities.nix ];
  options.programs.voiceDictation = {
    enable = lib.mkEnableOption "free offline system-wide voice dictation";
    package = lib.mkOption {
      type = lib.types.package;
      default = if isDarwin then pkgs.handy else (pkgs.voxtype.override { onnxSupport = true; });
      description = "Handy on Darwin or Voxtype on Linux.";
    };
    prepare = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = prepare;
      description = "Reconcile managed preferences and install the pinned model link while Handy is stopped.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ] ++ lib.optionals isDarwin [ prepare ];
    targets.darwin.copyApps.enable = lib.mkIf isDarwin (lib.mkDefault true);
    xdg.configFile."voxtype/config.toml" = lib.mkIf isLinux {
      source = (pkgs.formats.toml { }).generate "voxtype.toml" {
        engine = "parakeet";
        osd.enabled = false;
        state_file = "auto";
        hotkey.enabled = false;
        audio = {
          device = "default";
          max_duration_secs = 300;
          feedback.enabled = true;
        };
        parakeet = {
          model = toString model;
          model_type = "tdt";
          on_demand_loading = true;
        };
        output = {
          mode = "paste";
          fallback_to_clipboard = true;
          auto_submit = false;
          notification = {
            on_recording_start = true;
            on_recording_stop = true;
            on_transcription = false;
          };
        };
      };
    };
    systemd.user.services.voxtype = lib.mkIf isLinux {
      Unit = {
        Description = "Offline voice dictation";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe cfg.package} --config ${config.xdg.configHome}/voxtype/config.toml daemon";
        ExecStartPost = lib.getExe registerBindings;
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    wayland.windowManager.hyprland.settings.bind = lib.mkIf isLinux (
      lib.mkAfter (
        map (action: bind linuxChords.${action} actions.${action}) (builtins.attrNames shortcutKeys)
      )
    );
    launchd.agents.handy = lib.mkIf isDarwin {
      enable = true;
      config = {
        Label = "com.pais.handy.service";
        ProgramArguments = [ (lib.getExe start) ];
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ThrottleInterval = 5;
        ProcessType = "Interactive";
      };
    };
    macos.applicationCapabilities.apps.handy = lib.mkIf isDarwin {
      enable = true;
      bundle = "Handy.app";
      bundleId = "com.pais.handy";
      features = {
        recording = {
          enable = true;
          service = "microphone";
          reason = "Record speech only while dictation is active";
          source = "https://github.com/cjpais/Handy";
          instruction = "Start dictation in Handy and allow microphone access when macOS asks.";
        };
        paste = {
          enable = true;
          service = "accessibility";
          reason = "Paste the completed transcript into the focused text field";
          source = "https://github.com/cjpais/Handy";
          instruction = "Allow Handy in Privacy & Security > Accessibility, then dictate into an unsent draft.";
        };
      };
    };
  };
}
