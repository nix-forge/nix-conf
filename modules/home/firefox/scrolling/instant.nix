{
  programs.firefox.profiles.default.settings =
    # Recommended for 60hz+ displays
    {
      "apz.overscroll.enabled" = true;
      "general.smoothScroll" = true;
      "mousewheel.default.delta_multiplier_y" = 275;
      "general.smoothScroll.msdPhysics.enabled" = false;
    };
}
