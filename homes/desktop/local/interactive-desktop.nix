{ lib, pkgs, ... }: {
  # Keep the workstation's interactive shell explicit. The generic modules
  # remain reusable in lightweight, recovery, and non-Hyprland profiles.
  desktop.enable = true;
  desktop.noctalia.enable = true;
  # This host renders a single virtual Sunshine output. Night light works at
  # the compositor layer without an external network lookup; brightness does
  # not, so hide that non-functional control rather than exposing a dead UI.
  desktop.noctalia = {
    nightLight.enable = true;
    brightness = {
      enable = true;
      disabledOutputs = [ "SUNSHINE" ];
    };
  };
  desktop.bar.networkCommand = "iwgtk";
  desktop.applications.networkBackend = "iwd";
  desktop.applications.sessionLauncher = "uwsm app --";
  desktop.workflow.terminalCommand = "uwsm app -- ${lib.getExe pkgs.ghostty}";

  # Source selection is declarative. NASA's Image and Video Library has
  # curated mission photography; SVS remains available as an opt-in source
  # for users who specifically want scientific visualisations.
  desktop.wallpaper.enable = true;
  desktop.wallpaper.sources.nasaSvs.enable = false;
  desktop.wallpaper.sources.nasaImageLibrary.enable = true;
  desktop.wallpaper.sources.clevelandMuseum.enable = true;
  desktop.wallpaper.sources.wikimediaCommons.enable = true;
  desktop.wallpaper.sources.smithsonian.enable = true;
}
