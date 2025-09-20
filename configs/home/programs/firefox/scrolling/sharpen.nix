{ lib }:
let
  inherit (lib.cust.firefox) toUserJS;
  extraConfig = lib.strings.concatLines [
    "/* Smoothfox preset: Sharpen Scrolling */"
    (toUserJS {
      "apz.overscroll.enabled" = true;
      "general.smoothScroll" = true;
      "mousewheel.min_line_scroll_amount" = 10;
      "general.smoothScroll.mouseWheel.durationMinMS" = 80;
      "general.smoothScroll.currentVelocityWeighting" = "0.15";
      "general.smoothScroll.stopDecelerationWeighting" = "0.6";
      "general.smoothScroll.msdPhysics.enabled" = false;
    })
  ];
in
{
  key = "sharpen";
  name = "Sharpen Scrolling";
  inherit extraConfig;
}
