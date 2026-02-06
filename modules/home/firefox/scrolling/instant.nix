{ lib }:
let
  inherit (lib.cust.firefox) toUserJS;
  extraConfig = lib.strings.concatLines [
    # Recommended for 60hz+ displays
    "/* Smoothfox preset: Instant Scrolling (Simple Adjustment) */"
    (toUserJS {
      "apz.overscroll.enabled" = true;
      "general.smoothScroll" = true;
      "mousewheel.default.delta_multiplier_y" = 275;
      "general.smoothScroll.msdPhysics.enabled" = false;
    })
  ];
in
{
  key = "instant";
  name = "Instant Scrolling";
  inherit extraConfig;
}
