{
  config,
  lib,
  pkgs,
  ...
}:
let
  jellyfin = config.services.jellyfin;
  seerrUrl = "http://127.0.0.1:${toString config.services.seerr.port}";

  # Keep package recipes in nixpkgs-personal and compatibility policy here.
  subtitleExtract = pkgs.jellyfin-plugin-subtitle-extract;
  introSkipper = pkgs.jellyfin-plugin-intro-skipper;
  moonbase = pkgs.jellyfin-plugin-moonbase;
in
{
  assertions = lib.optionals jellyfin.enable [
    {
      assertion =
        lib.versionAtLeast jellyfin.package.version "12.1"
        && lib.versionOlder jellyfin.package.version "13";
      message = "The selected plugins target Jellyfin 12; review the plugin API before a server major upgrade.";
    }
  ];

  homelab.optional.jellyfinPlugins.packages = lib.mkIf jellyfin.enable {
    "Subtitle Extract_nix" = subtitleExtract;
    "Intro Skipper_nix" = introSkipper;
    "Moonfin_nix" = moonbase;
  };
  homelab.optional.jellyfinPlugins.moonbase = lib.mkIf jellyfin.enable {
    enable = true;
    inherit seerrUrl;
  };
  # Intro Skipper probes EncoderAppPathDisplay, falling back to `ffmpeg` when
  # that setting is absent. Use Jellyfin's Chromaprint-enabled build in both
  # cases, including during first-run setup before encoding.xml exists.
  systemd.services.jellyfin.path = lib.mkIf jellyfin.enable [ pkgs.jellyfin-ffmpeg ];
}
