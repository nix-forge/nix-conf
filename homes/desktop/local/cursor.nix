{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = config.wayland.windowManager.hyprland.displayScaling.cursor.resolvedSize;
  personalPackages = inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system};
  # The Hyprcursor package is supplied by nixpkgs-personal. Keep evaluation
  # compatible with a lock that predates that package; the standard XCursor
  # package preserves a working pointer while the dependency update lands.
  cursorPackage = personalPackages.bibata-cursors-hyprcursor or pkgs.bibata-cursors;
in
{
  # Bibata Modern Ice is a white, rounded Material-style pointer with a dark
  # outline.  It stays legible over the dark desktop and busy game UIs, while
  # the packaged theme provides native XCursor assets at this exact size.
  # Use the personal package built from the official Bibata source. It provides
  # native Hyprcursor assets and an XCursor fallback without an imperative
  # download or a legacy-only theme conversion at activation time.
  # Stylix owns Home Manager's pointerCursor settings when it is enabled. Set
  # its cursor values here rather than defining the generated options a second
  # time, keeping the complete desktop profile composable with Stylix.
  stylix.cursor = {
    package = lib.mkForce cursorPackage;
    name = lib.mkForce cursorTheme;
    size = lib.mkForce cursorSize;
  };

  # The reusable Hyprland display-scaling module derives the size from this
  # desktop's output scale; this local file selects the package and theme.
  # `local/hyprland.nix` renders these resolved Stylix cursor values into the
  # existing UWSM environment template with `lib.replaceVars`.

  home.sessionVariables = {
    HYPRCURSOR_THEME = cursorTheme;
    HYPRCURSOR_SIZE = toString cursorSize;
    XCURSOR_THEME = cursorTheme;
    XCURSOR_SIZE = toString cursorSize;
  };
}
