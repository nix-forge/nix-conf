{
  programs.linearmouse = {
    enable = true;
    menuBarVisibility = "never";
    menuBarBatteryDisplay = "off";
    showInDock = false;
    settings = {
      schemes = [
        {
          "if" = {
            device = {
              category = "mouse";
            };
          };
          pointer = {
            # Keep macOS's adaptive acceleration and the device/system
            # tracking speed. A numeric acceleration of 0 is not the same
            # as disabling acceleration in LinearMouse.
            acceleration = "unset";
            speed = "unset";
            disableAcceleration = false;
          };
          scrolling = {
            reverse = {
              vertical = true;
            };
          };
        }
      ];
    };
  };
}
