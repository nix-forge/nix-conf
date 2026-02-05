{
  system.defaults = {
    NSGlobalDomain = {
      # Disable window animations
      NSAutomaticWindowAnimationsEnabled = false;

      # Minimize window resize time
      NSWindowResizeTime = 0.001;

      # Disable scroll animations
      NSScrollAnimationEnabled = false;
    };

    dock = {
      # Expose animation duration
      expose-animation-duration = 0.1;

      # Remove animation when hiding/showing Dock
      autohide-time-modifier = 0.0;

      # Remove auto-hiding delay
      autohide-delay = 0.0;

      # Don't animate opening applications from the Dock
      launchanim = false;
    };

    CustomUserPreferences = {
      # Disable send and reply animations in Mail.app
      "com.apple.Mail" = {
        DisableReplyAnimations = true;
        DisableSendAnimations = true;
      };

      "com.apple.dock" = {
        # Springboard animation duration
        springboard-show-duration = 0.1;
        springboard-hide-duration = 0.1;
        expose-group-apps = 0.1;
      };

      "com.apple.finder" = {
        # Disable Finder animations
        DisableAllAnimations = true;
      };
    };
  };
}
