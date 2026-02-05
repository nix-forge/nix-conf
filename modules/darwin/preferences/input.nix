{
  system.defaults = {
    trackpad = {
      # Enable trackpad tap to click
      Clicking = true;

      # Enable tap-to-drag
      Dragging = false;

      # Enable trackpad right click
      TrackpadRightClick = true;

      # Three finger drag
      TrackpadThreeFingerDrag = false;
    };

    CustomUserPreferences = {
      # Map bottom right Trackpad corner to right-click
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        TrackpadCornerSecondaryClick = 2;
        TrackpadRightClick = true;
      };
    };
  };
}
