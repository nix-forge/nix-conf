{ pkgs, lib, ... }:
{
  # Avoid the Linux kernel locking itself when we're putting too much strain on the memory
  services.earlyoom = {
    enable = true;
    enableNotifications = true; # be notified when earlyoom kills a process
    reportInterval = 0;
    freeSwapThreshold = 2;
    freeMemThreshold = 4;
    extraArgs =
      let
        # applications that we would like to avoid killing
        # when system is under high memory pressure
        appsToAvoid = lib.concatStringsSep "|" [
          "Hyprland" # avoid killing the graphical session
          "foot" # terminal, might have unsaved files
          "cryptsetup" # avoid killing the disk encryption manager
          "dbus-.*" # avoid killing the dbus daemon & the dbus broker
          "Xwayland" # avoid killing the X11 server
          "gpg-agent" # avoid killing the gpg agent
          "systemd" # avoid killing systemd
          "systemd-.*" # avoid killing systemd microservices
          "ssh-agent" # avoid killing the ssh agent
        ];

        # apps that we would like killed first
        # likely the ones draining most memory
        appsToPrefer = lib.concatStringsSep "|" [
          # browsers
          "Web Content"
          "Isolated Web Co"
          "chromium.*"
          # electron applications
          "electron"
          ".*.exe"
          "java.*"
          # PipeWire could lock system as it could fail to acquire RT privileges
          "pipewire(.*)" # catch pipewire and pipewire-pulse
        ];
      in
      [
        "-g" # kill all processes within a process group
        "--avoid '^(${appsToAvoid})$'" # things we want to not kill
        "--prefer '^(${appsToPrefer})$'" # things we want to kill as soon as possible
      ];

    # we should ideally write the logs into a designated log file; or even better, to the journal
    # for now we can hope this echo sends the log to somewhere we can observe later
    killHook = pkgs.writeShellScript "earlyoom-kill-hook" ''
      echo "Process $EARLYOOM_NAME ($EARLYOOM_PID) was killed"
    '';
  };

  systemd.services.earlyoom.serviceConfig = {
    # from upstream
    DynamicUser = true;
    AmbientCapabilities = "CAP_KILL CAP_IPC_LOCK";
    Nice = -20;
    OOMScoreAdjust = -100;
    ProtectSystem = "strict";
    ProtectHome = true;
    Restart = "always";
    TasksMax = 10;
    MemoryMax = "50M";

    # Protection rules. Mostly from the `systemd-oomd` service
    # with some of them already included upstream.
    CapabilityBoundingSet = "CAP_KILL CAP_IPC_LOCK";
    PrivateDevices = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;

    PrivateNetwork = true;
    IPAddressDeny = "any";
    RestrictAddressFamilies = "AF_UNIX";

    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@resources @privileged"
    ];
  };
}
