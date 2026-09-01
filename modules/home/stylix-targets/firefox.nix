{
  # Firefox Color stores the generated palette as managed extension settings.
  # Keep all extension settings for this declarative profile under Home
  # Manager's ownership rather than silently merging stale profile state.
  programs.firefox.profiles.default.extensions.force = true;

  stylix.targets.firefox = {
    enable = true;
    profileNames = [ "default" ];
    # Generate Firefox Color from the selected Stylix palette. This themes
    # browser chrome without competing userChrome.css files.
    colorTheme.enable = true;
  };
}
