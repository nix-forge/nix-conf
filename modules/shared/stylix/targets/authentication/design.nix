{
  render =
    { config }:
    let
      colors = config.lib.stylix.colors.withHashtag;
      # Reuse the shell's fixed semantic roles. Both authentication renderers
      # consume this specification; no home-to-greeter mutable sync is needed.
      palette = (import ../noctalia/palette.nix).render { inherit colors; };
      # Use the shell's conversion from Stylix points to logical text pixels.
      # Text scaling is independent of the authentication controls' hit targets.
      fontScale = (config.stylix.fonts.sizes.desktop * 4.0 / 3.0) / 14.0;
    in
    {
      font = config.stylix.fonts.sansSerif.name;
      inherit fontScale;
      fontSizes = {
        caption = 13 * fontScale;
        body = 14 * fontScale;
        title = 16 * fontScale;
        clock = 48 * fontScale;
      };
      borderWidth = 1;
      focusWidth = 2;
      panelWidth = 540;
      inputHeight = 48;
      panelRadius = 12;
      inputRadius = 6;
      inputPadding = 15;
      padding = 16;
      gap = 8;
      panelHeight = 306;
      clockY = 244;
      dateY = 196;
      avatarY = 97;
      accountY = 44;
      inputY = -13;
      footerY = -67;
      statusY = -105;
      keyboardY = -129;
      timeFormat = "%-I:%M %p";
      dateFormat = "%a, %b %-d";
      inherit colors;
      greeterPalette = {
        primary = palette.dark.mPrimary;
        on_primary = palette.dark.mOnPrimary;
        secondary = palette.dark.mSecondary;
        on_secondary = palette.dark.mOnSecondary;
        tertiary = palette.dark.mTertiary;
        on_tertiary = palette.dark.mOnTertiary;
        error = palette.dark.mError;
        on_error = palette.dark.mOnError;
        surface = palette.dark.mSurface;
        on_surface = palette.dark.mOnSurface;
        surface_variant = palette.dark.mSurfaceVariant;
        # Small authentication hints need full text contrast. The raw muted
        # Base16 role can fall below 4.5:1 on the card; hierarchy comes from
        # type size here, without relying on the shell's palette rewriting.
        on_surface_variant = palette.dark.mOnSurface;
        outline = palette.dark.mOutline;
        shadow = palette.dark.mShadow;
        hover = palette.dark.mHover;
        on_hover = palette.dark.mOnHover;
      };
    };
}
