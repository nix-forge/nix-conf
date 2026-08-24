{ lib, pkgs, ... }: {
  security.polkit = {
    # This is an owner-administered workstation.  Wheel is the sole Polkit
    # administrator identity, matching the sudo policy; do not add the root
    # account or an ordinary desktop user as an alternative prompt identity.
    adminIdentities = [ "unix-group:wheel" ];

    # The workstation's GUI uses D-Bus Polkit actions, not a general setuid
    # root command launcher.  Keep `pkexec` absent unless a specific reviewed
    # application requires it.
    enablePkexecWrapper = lib.mkForce false;

    # Keep the upstream five-minute authorization cache for a short sequence
    # of storage or firmware operations.  This is deliberately finite and is
    # scoped by Polkit to the action and subject, not a session-wide sudo grant.
    settings.Polkitd.ExpirationSeconds = 300;
    extraArgs = [
      "--no-debug"
      "--log-level=notice"
    ];
  };

  # Greetd launches a dedicated Hyprland Wayland session for this desktop.
  # Keep exactly one agent in that graphical session so UDisks, fwupd, and
  # other GUI mechanisms can request an administrator password.  This
  # established GTK agent is retained because it is currently healthy on the
  # deployed workstation; choose a different agent only as an explicit,
  # tested desktop UX migration.
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "GNOME Polkit Authentication Agent";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
