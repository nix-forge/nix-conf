{
  targets.darwin.defaults = {
    NSGlobalDomain = {
      "com.apple.swipescrolldirection" = true;
    };

    "com.apple.AppleMultitouchTrackpad" = {
      Clicking = true;
      Dragging = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
    };

    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
      Clicking = true;
      Dragging = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
      TrackpadCornerSecondaryClick = 2;
    };
  };
}
