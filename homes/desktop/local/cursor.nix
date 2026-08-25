{ lib, pkgs, ... }:
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
  # Stylix owns Home Manager's pointerCursor settings when it is enabled. Set
  # its cursor values here rather than defining the generated options a second
  # time, keeping the complete desktop profile composable with Stylix.
  stylix.cursor = {
    package = lib.mkForce pkgs.bibata-cursors;
    name = lib.mkForce cursorTheme;
    size = lib.mkForce cursorSize;
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
