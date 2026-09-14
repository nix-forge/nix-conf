{
  config,
  lib,
  pkgs,
  ...
}:
let
  steam = lib.getExe config.programs.steam.package;
in
{
  # Preserve Sunshine's NVIDIA capture/conversion path without making every
  # CUDA-aware package in the desktop closure select its CUDA variant.
  services.sunshine.package = pkgs.sunshine.override { cudaSupport = true; };
  nix.caches.cuda.enable = true;

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

  # Require greetd's normal password authentication before starting a user
  # desktop. Sunshine is available after login; an asynchronous screen locker
  # is not a gate for boot-time autologin.
  assertions = [
    {
      assertion = !(config.services.greetd.settings ? initial_session);
      message = "The desktop requires authenticated greetd login before starting Sunshine.";
    }
  ];

  systemd.user.services.sunshine = {
    # Retry if the physical output is still completing its initial modeset
    # when the graphical session reaches its target.
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce "5s";
    };
  };

}
