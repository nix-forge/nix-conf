_: {
  # The upstream module adds the configured Hyprland/GTK portal backends and
  # PulseAudio compatibility libraries to Zoom's FHS environment. Installing
  # plain pkgs.zoom-us alone leaves its portal support disabled.
  programs.zoom-us.enable = true;
}
