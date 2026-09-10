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
}
