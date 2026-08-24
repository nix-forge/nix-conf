{
  config,
  lib,
  pkgs,
  ...
}:
let
  hyprctl = "${config.programs.hyprland.package}/bin/hyprctl";
  jq = lib.getExe pkgs.jq;
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

    # 1080p60 is deliberately the conservative no-hardware baseline.  It is
    # universally decodable on the MacBook, avoids an unnecessary 4K encode
    # load, and can be raised later after a stable stream is confirmed.
    ${hyprctl} eval 'hl.monitor({ output = "${headlessOutput}", mode = "1920x1080@60", position = "0x0", scale = 1 })'
  '';
in
{
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
