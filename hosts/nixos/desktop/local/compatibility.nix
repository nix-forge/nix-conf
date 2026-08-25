{ lib, ... }: {
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

  environment.gnome.excludePackages = [ ];

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
