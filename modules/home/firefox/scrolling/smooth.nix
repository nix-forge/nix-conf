{
  programs.firefox.profiles.default.settings =
    # Recommended for 90hz+ displays
    {
      "apz.overscroll.enabled" = true;
      "general.smoothScroll" = true;
      "general.smoothScroll.msdPhysics.enabled" = true;
      "mousewheel.default.delta_multiplier_y" = 300;
    };
}
