{ lib }:
let
  inherit (lib.cust.firefox) toUserJS;
  extraConfig = lib.strings.concatLines [
    # Recommended for 120hz+ displays
    "/* Smoothfox preset: Natural Smooth Scrolling v3 (Modified) */"
    (toUserJS {
      "apz.overscroll.enabled" = true;
      "general.smoothScroll" = true;
      "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
      "general.smoothScroll.msdPhysics.enabled" = true;
      "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
      "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
      "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
      "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = 2;
      "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
      "general.smoothScroll.currentVelocityWeighting" = "1";
      "general.smoothScroll.stopDecelerationWeighting" = "1";
      "mousewheel.default.delta_multiplier_y" = 300;
    })
  ];
in
{
  key = "natural";
  name = "Natural Smooth Scrolling";
  inherit extraConfig;
}
