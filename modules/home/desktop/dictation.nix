{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cfg = config.programs.voiceDictation;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  dataDir =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/com.pais.handy"
    else
      "${config.xdg.dataHome}/com.pais.handy";
  # Package metadata owns model identity, immutable pins and update automation.
  model = cfg.modelPackage;
  binding = id: chord: {
    inherit id;
    name = id;
    description = "Local voice dictation";
    default_binding = chord;
    current_binding = chord;
  };
  preferences = (pkgs.formats.json { }).generate "handy-preferences.json" {
    selected_model = model.modelId;
    # Keep weights warm during a dictation session; release memory after idle.
    model_unload_timeout = "min5";
    transcribe_accelerator = "auto";
    always_on_microphone = false;
    keyboard_implementation = "handy_keys";
    shortcut_activation = "push_to_talk";
    overlay_style = "live";
    overlay_position = "bottom";
    audio_feedback = true;
    audio_feedback_volume = 0.4;
    start_hidden = true;
    autostart_enabled = false; # The native service manager owns its lifetime.
    update_checks_enabled = false; # Nix owns updates.
    # Native normalization and the editable vocabulary still apply without an LLM.
    filler_word_removal_enabled = true;
    post_process_enabled = false;
    auto_submit = false;
    paste_method = "ctrl_v";
    clipboard_handling = "dont_modify";
    selected_language = "en";
    translate_to_english = false;
    recording_retention_period = "never";
    log_level = "warn";
    bindings = {
      transcribe = binding "transcribe" (if isDarwin then "option_left+space" else "alt_left+space");
      transcribe_with_post_process = binding "transcribe_with_post_process" "";
      # D is a named workspace in the shared keyboard scheme; Shift sends
      # a window there. Keep dictation cancellation out of that family.
      cancel = binding "cancel" (
        if config.keyboard.macosShortcuts.enable or false then "ctrl+alt+shift+x" else "ctrl+alt+shift+d"
      );
    };
  };
  reconciler = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).dictationReconcile;
  prepareArgs = [
    (lib.getExe reconciler)
    "--data-dir"
    dataDir
    "--preferences"
    preferences
    "--model"
    model.modelFile
    "--model-name"
    model.modelFilename
  ];
  prepare = writeShellApplication {
    name = "prepare-voice-dictation";
    text = "exec ${lib.escapeShellArgs prepareArgs}";
  };
  systemdUtils = import (pkgs.path + "/nixos/lib/utils.nix") { inherit lib config pkgs; };
  launcher =
    if isDarwin then
      "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Handy.app/Contents/MacOS/handy"
    else
      lib.getExe cfg.package;
  start = writeShellApplication {
    name = "start-voice-dictation";
    text = ''
      ${lib.getExe prepare}
      export HANDY_DISABLE_UPDATER=1
      exec ${lib.escapeShellArg launcher} --start-hidden
    '';
  };
in
{
  imports = [ ../macos/application-capabilities.nix ];
  options.programs.voiceDictation = {
    enable = lib.mkEnableOption "free offline system-wide voice dictation";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.handy;
      description = "Handy desktop dictation application.";
    };
    modelPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.parakeet-unified-en-gguf;
      description = "Speech model package exposing modelId, modelFilename and modelFile metadata.";
    };
    prepare = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = prepare;
      description = "Reconcile managed preferences and install the pinned model link while Handy is stopped.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
      prepare
    ];
    targets.darwin.copyApps.enable = lib.mkIf isDarwin (lib.mkDefault true);
    systemd.user.services.handy = lib.mkIf isLinux {
      Unit = {
        Description = "Offline voice dictation with recording overlay";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStartPre = systemdUtils.escapeSystemdExecArgs prepareArgs;
        ExecStart = systemdUtils.escapeSystemdExecArgs [
          launcher
          "--start-hidden"
        ];
        Environment = [
          "HANDY_DISABLE_UPDATER=1"
          "GDK_BACKEND=wayland"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
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
      teamId = "UWFLB4GC25";
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
