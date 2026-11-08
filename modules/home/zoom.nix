{
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  systemZoom = osConfig != null && (osConfig.programs.zoom-us.enable or false);
in
{
  imports = [ ./macos/application-capabilities.nix ];
  # NixOS's Zoom module includes the active desktop's portal backends in the
  # FHS environment. Do not shadow that package with the bare Home package.
  home.packages = lib.optional (!systemZoom) pkgs.zoom-us;

  xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/zoommtg" = [ "Zoom.desktop" ];
      "x-scheme-handler/zoomus" = [ "Zoom.desktop" ];
      "application/x-zoom" = [ "Zoom.desktop" ];
    };
  };

  macos.applicationCapabilities.apps.zoom = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = lib.mkDefault true;
    bundle = "zoom.us.app";
    bundleId = "us.zoom.xos";
    teamId = "BJ4HAAB9B3";
    features = {
      voice = {
        enable = lib.mkDefault true;
        service = "microphone";
        reason = "Speak in Zoom meetings";
        source = "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064868";
        instruction = "Use the Zoom audio test and confirm the microphone signal.";
      };
      video = {
        enable = lib.mkDefault false;
        service = "camera";
        reason = "Use video in Zoom meetings";
        source = "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064868";
        instruction = "Preview the camera in Zoom settings.";
      };
      sharing = {
        enable = lib.mkDefault false;
        service = "screen-recording";
        reason = "Share a window in Zoom";
        source = "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064868";
        instruction = "Share a harmless test window from Zoom.";
      };
    };
  };
}
