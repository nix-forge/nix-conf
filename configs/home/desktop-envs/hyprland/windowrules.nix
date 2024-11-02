{
  wayland.windowManager.hyprland.settings = {
    windowrulev2 = [
      # only allow shadows for floating windows
      "noshadow, floating:0"

      "float,class:udiskie"

      # wlogout
      "fullscreen,class:wlogout"
      "fullscreen,title:wlogout"
      "noanim, title:wlogout"

      # spotify
      "tile, title:Spotify"
      "tile, class:^(Spotify)$"

      # steam settings window
      "float, title:^(Steam Settings)$"

      # telegram media viewer
      "float, title:^(Media viewer)$"

      # bitwarden
      "float,class:Bitwarden"
      "size 800 600,class:Bitwarden"

      "idleinhibit focus, class:^(mpv)$"
      "idleinhibit focus,class:foot"

      # firefox
      "idleinhibit fullscreen, class:^(firefox)$"
      "float,title:^(Firefox — Sharing Indicator)$"
      "move 0 0,title:^(Firefox — Sharing Indicator)$"
      "float, title:^(Picture-in-Picture)$"
      "pin, title:^(Picture-in-Picture)$"

      # pavucontrol
      "float,class:pavucontrol"
      "float,title:^(Volume Control)$"
      "size 800 600,title:^(Volume Control)$"
      "move 75 44%,title:^(Volume Control)$"
      "float, class:^(imv)$"

      # throw sharing indicators away
      "workspace special silent, title:^(Firefox — Sharing Indicator)$"
      "workspace special silent, title:^(.*is sharing (your screen|a window)\.)$"

      # wine
      "workspace special silent, title:^(title:Wine System Tray)$"

      # Xwayland Video Bridge
      "opacity 0.0 override, class:^(xwaylandvideobridge)$"
      "noanim, class:^(xwaylandvideobridge)$"
      "noinitialfocus, class:^(xwaylandvideobridge)$"
      "maxsize 1 1, class:^(xwaylandvideobridge)$"
      "noblur, class:^(xwaylandvideobridge)$"
    ];
  };
}
