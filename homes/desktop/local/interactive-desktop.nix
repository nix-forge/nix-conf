{
  # Keep the workstation's interactive shell explicit. The generic modules
  # remain reusable in lightweight, recovery, and non-Hyprland profiles.
  desktop.enable = true;
  desktop.bar.networkCommand = "iwgtk";
  desktop.applications.networkBackend = "iwd";

  # Source selection is declarative. Both enabled feeds populate one local
  # library, so rotation combines science visualisations with CC0 artwork.
  desktop.wallpaper.enable = true;
  desktop.wallpaper.sources.nasaSvs.enable = true;
  desktop.wallpaper.sources.clevelandMuseum.enable = true;
}
