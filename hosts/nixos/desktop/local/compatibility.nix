{ lib, ... }: {
  # Keep temporary compatibility local to this host while the shared modules
  # continue to track their intended, newer option set.
  services = {
    xserver.enable = true;
    desktopManager.gnome.enable = true;
    # Greetd owns graphical login on this host. A separate GDM login screen
    # would compete with the selected greeter for graphical login.
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
