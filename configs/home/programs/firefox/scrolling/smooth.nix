{ lib }:
let
  inherit (lib.cust.firefox) toUserJS;
  extraConfig = lib.strings.concatLines [
    # Recommended for 90hz+ displays
    "/* Smoothfox preset: Smooth Scrolling */"
    (toUserJS {
      "apz.overscroll.enabled" = true;
      "general.smoothScroll" = true;
      "general.smoothScroll.msdPhysics.enabled" = true;
      "mousewheel.default.delta_multiplier_y" = 300;
    })
  ];
in
{
  key = "smooth";
  name = "Smooth Scrolling";
  inherit extraConfig;
}
