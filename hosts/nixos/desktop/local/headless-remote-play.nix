{
  config,
  lib,
  pkgs,
  ...
}:
let
  hyprctl = "${config.programs.hyprland.package}/bin/hyprctl";
  jq = lib.getExe pkgs.jq;
  steam = lib.getExe config.programs.steam.package;
  headlessOutput = "SUNSHINE";
  prepareHeadlessOutput = pkgs.replaceVarsWith {
    name = "prepare-sunshine-headless-output";
    src = ./scripts/prepare-sunshine-headless-output.sh;
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      seq = lib.getExe' pkgs.coreutils "seq";
      sleep = lib.getExe' pkgs.coreutils "sleep";
      inherit hyprctl jq;
      inherit headlessOutput;
    };
  };
in
{
  # This is desktop-user behaviour, not a generic Sunshine policy. Steam is
  # explicitly detached because it replaces its bootstrap process during
  # startup. Do not add an undo command: Sunshine runs undo commands after a
  # Moonlight disconnect, and launching `steam://close/bigpicture` there starts
  # a new persistent Steam process under Sunshine. That orphaned process kept
  # the control/cancel endpoint busy until Moonlight timed out.
  services.sunshine.applications.apps = [
    {
      name = "Desktop";
      "image-path" = "desktop.png";
    }
    {
      name = "Steam Big Picture";
      "image-path" = "steam.png";
      detached = [ "${steam} steam://open/bigpicture" ];
    }
  ];

  services.sunshine.settings = {
    # A 60 Mbit/s hard ceiling contains adaptive bitrate if the Wi-Fi radio
    # falls back again. Moonlight's 55 Mbit/s default remains below this cap.
    max_bitrate = 60000;

    # Keep AV1 Main10 available: both the RTX 4070 and M4 Pro support it.
    # The active wlroots capture path remains SDR; the profile is retained for
    # compatibility and a future supported HDR capture configuration.
    av1_mode = 3;
  };

  # With no physical monitor, a login manager cannot wait for interactive
  # credentials. Greetd directly starts the owner's local Wayland session on
  # boot so Sunshine has a capture target. `sunshine-session-lock` immediately
  # authenticates the session through Hyprlock before it becomes usable; that
  # same PAM transaction unlocks the GNOME Login keyring.
  services.greetd.settings.initial_session = {
    # GPU and toolkit variables live in the user's UWSM environment files.
    # Keeping this command free of hardware assignments means the exact same
    # UWSM session path is used by greetd and an interactive display manager.
    command = "${lib.getExe config.programs.uwsm.package} start hyprland-uwsm.desktop";
    user = "ianmh";
  };

  # Sunshine's wlroots backend sees this virtual output even though every DRM
  # connector is disconnected.  Do not set Sunshine output_name: this session
  # has exactly one output, which avoids backend-specific output-name handling.
  systemd.user.services.sunshine-headless-output = {
    description = "Create the Hyprland virtual output used by Sunshine";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig = {
      Before = "sunshine.service";
      ConditionUser = "ianmh";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStartSec = "150s";
      ExecStart = prepareHeadlessOutput;
    };
  };

  systemd.user.services.sunshine = {
    # Do not make Sunshine's job fail permanently if the compositor is still
    # coming up. `Requires` propagates the first headless-output failure even
    # though that unit is configured to retry. Pull it in softly, then run the
    # same readiness operation as Sunshine's pre-start gate. A transient
    # Hyprland delay now becomes a normal restartable Sunshine start failure,
    # not an inactive service until someone logs in and starts it manually.
    unitConfig = {
      Wants = [ "sunshine-headless-output.service" ];
      After = lib.mkForce "graphical-session.target sunshine-headless-output.service";
    };
    serviceConfig = {
      ExecStartPre = lib.mkBefore [ prepareHeadlessOutput ];
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce "5s";
    };
  };

  # Autologin cannot unlock an encrypted keyring: it deliberately supplies no
  # password to PAM. Lock the auto-started session instead of weakening or
  # removing its keyring password. This leaves a headless capture target for
  # Sunshine while making the first Moonlight/console interaction a normal
  # password authentication, which unlocks both Hyprlock and GNOME Keyring.
  systemd.user.services.sunshine-session-lock = {
    description = "Lock the auto-started Sunshine session before use";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig = {
      After = [
        "graphical-session.target"
        "sunshine-headless-output.service"
      ];
      ConditionUser = "ianmh";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe config.programs.hyprlock.package;
      Restart = "no";
    };
  };
}
