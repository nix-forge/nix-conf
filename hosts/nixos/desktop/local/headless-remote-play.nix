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
  prepareHeadlessOutput = pkgs.writeShellScript "prepare-sunshine-headless-output" ''
    set -eu

    # UWSM exports the Wayland and Hyprland instance environment to services
    # activated by graphical-session.target.  Wait for the compositor socket
    # rather than relying on a timing-sensitive Hyprland exec-once directive.
    ready=0
    # A cold NVIDIA/Wayland boot can take longer than the nominal graphical
    # session target. Keep waiting for the compositor's actual control socket
    # instead of failing Sunshine's first startup attempt at an arbitrary
    # short threshold.
    for attempt in $(${pkgs.coreutils}/bin/seq 1 120); do
      if ${hyprctl} monitors -j >/dev/null 2>&1; then
        ready=1
        break
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    if [ "$ready" -ne 1 ]; then
      echo "Hyprland did not become ready for the Sunshine virtual output" >&2
      exit 1
    fi

    if ! ${hyprctl} monitors -j | ${jq} -e --arg output ${headlessOutput} \
      '.[] | select(.name == $output)' >/dev/null; then
      ${hyprctl} output create headless ${headlessOutput}
    fi

    for attempt in $(${pkgs.coreutils}/bin/seq 1 10); do
      if ${hyprctl} monitors -j | ${jq} -e --arg output ${headlessOutput} \
        '.[] | select(.name == $output)' >/dev/null; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done

    # Keep the MacBook Pro's non-standard panel aspect ratio without requiring
    # native-resolution streaming. 2560x1655 is an aspect-ratio match to
    # rounding precision and costs roughly 45% fewer pixels than 3456x2234 at
    # 120 Hz, preserving smooth input and presentation without overloading
    # NVENC or the current Wi-Fi link.
    #
    # Sunshine's wlroots screencopy backend is the right unprivileged capture
    # method for this headless Hyprland session, but it cannot transport HDR
    # metadata. Keep the virtual output explicitly SDR rather than allowing
    # games to render HDR that Sunshine would then mislabel as SDR. Genuine
    # Linux HDR capture requires Sunshine's privileged KMS backend and a
    # suitable DRM-attached HDR display; neither is appropriate here.
    ${hyprctl} eval 'hl.monitor({ output = "${headlessOutput}", mode = "2560x1655@120", position = "0x0", scale = 1, bitdepth = 8, cm = "srgb", supports_wide_color = 0, supports_hdr = 0 })'
  '';
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
  # credentials.  Greetd directly starts the owner's local Wayland session on
  # boot.  LAN firewalling plus Moonlight's pairing and encryption still guard
  # remote access; anyone with physical console access can reach this session.
  services.greetd.settings.initial_session = {
    command = "env AQ_DRM_DEVICES=/dev/dri/card1 GBM_BACKEND=nvidia-drm ${lib.getExe config.programs.uwsm.package} start hyprland-uwsm.desktop";
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
}
