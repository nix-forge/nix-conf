{
  targets.darwin.defaults = {
    NSGlobalDomain = {
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      NSScrollAnimationEnabled = false;
    };

    "com.apple.dock" = {
      expose-animation-duration = 0.1;
      autohide-time-modifier = 0.0;
      autohide-delay = 0.0;
      launchanim = false;
      springboard-show-duration = 0.1;
      springboard-hide-duration = 0.1;
    };

    "com.apple.Mail" = {
      DisableReplyAnimations = true;
      DisableSendAnimations = true;
    };

    "com.apple.finder".DisableAllAnimations = true;
  };
}
