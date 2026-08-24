{ pkgs, ... }:
let
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 24;
in
{
  # Bibata Modern Ice is a white, rounded Material-style pointer with a dark
  # outline.  It stays legible over the dark desktop and busy game UIs, while
  # the packaged theme provides native XCursor assets at this exact size.
  # Use the already packaged Nixpkgs derivation rather than duplicating or
  # downloading a cursor theme imperatively.
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = cursorTheme;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  # Bibata supplies XCursor assets, not a Hyprcursor theme. Keep the values in
  # Home Manager's session environment for toolkits outside GTK/X11 too. The
  # Lua backend in Home Manager currently renders Hyprland's `env` and `cursor`
  # settings with an obsolete function signature, so setting either through
  # `wayland.windowManager.hyprland.settings` would put Hyprland into emergency
  # mode and disable all normal key bindings.
  home.sessionVariables = {
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
  };
}
