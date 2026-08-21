{ lib, pkgs, ... }: {
  # Keep temporary compatibility local to this host while the shared modules
  # continue to track their intended, newer option set.
  services = {
    xserver.enable = true;
    desktopManager.gnome.enable = true;
    # The workstation has no attached display.  Greetd starts the dedicated
    # Hyprland session defined in headless-remote-play.nix instead of leaving
    # a graphical GDM login screen that Sunshine cannot capture.
    displayManager.gdm.enable = lib.mkForce false;
  };

  programs.dconf.enable = true;
  environment.gnome.excludePackages = [ ];

  security.polkit.enable = true;
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
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

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
