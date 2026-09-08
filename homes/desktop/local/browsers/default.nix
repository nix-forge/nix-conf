{
  imports = [
    ../../../shared/local/browsers/common.nix
    ../../../shared/local/browsers/bitwarden.nix
    ../../../shared/local/browsers/extensions.nix
    ../../../shared/local/browsers/search.nix
    ../../../shared/local/browsers/zen.nix
  ];

  # Blocky and Unbound own encrypted DNS on this host. Avoid sending a second,
  # conflicting DNS policy through each browser.
  programs.browserSuite.systemResolverPolicy.DNSOverHTTPS = {
    Enabled = false;
    Locked = true;
  };

  # Gecko 154's HDR compositor exposes rounded tile cutouts in Hyprland.
  # Forcing Zen onto the AMD iGPU also makes ordinary pages render black
  # through the NVIDIA output. Keep the normal GPU path and explicitly reset
  # both preferences, including profiles that previously enabled the trial.
  programs.zen-browser.profiles.default.settings = {
    "gfx.color_management.hdr" = false;
    "gfx.color_management.hdr.force_enabled" = false;
  };
}
