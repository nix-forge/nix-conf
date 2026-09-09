{ config, lib, ... }: {
  home.file."${config.xdg.configHome}/electron-flags.conf".text = lib.concatLines [
    "--enable-features=UseOzonePlatform"
    "--ozone-platform=wayland"
    "--enable-features=WebRTCPipeWireCapturer"
    "--enable-features=WaylandWindowDecorations"
  ];
}
