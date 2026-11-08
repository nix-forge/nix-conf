{
  imports = [ ./session.nix ];

  services.displayManager.cosmic-greeter.enable = true;

  services.desktopManager.cosmic.enable = true;
}
