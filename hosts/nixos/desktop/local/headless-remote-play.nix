{
  config,
  lib,
  pkgs,
  ...
}:
let
  steam = lib.getExe config.programs.steam.package;
  hyprlock = lib.getExe config.programs.hyprlock.package;
  pidof = lib.getExe' pkgs.procps "pidof";
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

  # Start the owner's local Wayland session on boot so Sunshine is reachable
  # before someone uses the physical console. `sunshine-session-lock`
  # immediately authenticates the session through Hyprlock before it becomes
  # usable; that PAM transaction also unlocks the GNOME Login keyring.
  services.greetd.settings.initial_session = {
    # GPU and toolkit variables live in the user's UWSM environment files.
    # Keeping this command free of hardware assignments means the exact same
    # UWSM session path is used by greetd and an interactive display manager.
    command = "${lib.getExe config.programs.uwsm.package} start hyprland-uwsm.desktop";
    user = "ianmh";
  };

  systemd.user.services.sunshine = {
    # Retry if the physical output is still completing its initial modeset
    # when the graphical session reaches its target.
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce "5s";
    };
  };

  # Autologin cannot unlock an encrypted keyring: it deliberately supplies no
  # password to PAM. Lock the auto-started session instead of weakening or
  # removing its keyring password. This leaves a capture target for Sunshine
  # while making the first Moonlight or console interaction a normal
  # password authentication, which unlocks both Hyprlock and GNOME Keyring.
  systemd.user.services.sunshine-session-lock = {
    description = "Lock the auto-started Sunshine session before use";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig = {
      After = [ "graphical-session.target" ];
      ConditionUser = "ianmh";
    };
    serviceConfig = {
      Type = "simple";
      # Home Manager can reload this unit while the boot-time Hyprlock is
      # already holding the session lock. Treat that state as success instead
      # of starting a second lock client and degrading the user manager.
      ExecStart = "${lib.getExe pkgs.bash} -c '${pidof} hyprlock >/dev/null || exec ${hyprlock}'";
      Restart = "no";
    };
  };
}
