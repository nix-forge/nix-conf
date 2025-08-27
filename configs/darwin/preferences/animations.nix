{
  system.defaults = {
    # universalaccess = {
    #   reduceMotion = true;
    # };
    NSGlobalDomain = {
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      NSScrollAnimationEnabled = false;
      NSTextShowsControlCharacters = true;
    };
    dock = {
      expose-animation-duration = 0.1;
      autohide-time-modifier = 0.0;
      autohide-delay = 0.0;
    };

    CustomUserPreferences = {
      "com.apple.dock" = {
        springboard-show-duration = 0.1;
        springboard-hide-duration = 0.1;
        expose-group-apps = 0.1;
      };
      "com.apple.finder" = {
        DisableAllAnimations = true;
      };
    };
  };
}
