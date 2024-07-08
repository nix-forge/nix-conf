{ pkgs, ... }:
{
  # set the systemVersion for the entire configuration
  system.stateVersion = "24.11";

  # enable dconf
  programs.dconf.enable = true;
  environment.systemPackages = [ pkgs.dconf-editor ];

  services.dbus = {
    enable = true;
    packages = with pkgs; [
      dconf
      gcr
      udisks2
    ];

    # Use the faster dbus-broker instead of the classic dbus-daemon
    implementation = "broker";
  };

}
