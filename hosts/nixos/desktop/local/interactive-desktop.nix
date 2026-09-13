{ config, ... }: {
  appearance.theme = "carbon-neon-oled";
  desktop.system.enable = true;

  # UWSM owns Hyprland's environment and user-service lifecycle.
  services.displayManager.defaultSession = "hyprland-uwsm";
  services.displayManager.noctalia-greeter.settings = {
    # The greeter resolves the desktop entry's Name, not its filename.
    session.default = "Hyprland (uwsm-managed)";
    user.default = "ianmh";
    output = {
      # The greeter selects the highest advertised refresh for this mode.
      # Avoid pinning a connector so another DisplayPort socket still works.
      width = 3840;
      height = 2160;
      scale = 1.5;
    };
    idle.timeout = 60;
    keyboard = {
      inherit (config.services.xserver.xkb) layout variant options;
      numlock = true;
    };
    auth = {
      allow_empty_password = false;
      request_timeout = 60;
    };
  };
}
