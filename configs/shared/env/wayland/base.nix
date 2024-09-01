{
  XDG_SESSION_TYPE = "wayland";
  NIXOS_OZONE_WL = "1";

  GDK_BACKEND = "wayland";

  SDL_VIDEODRIVER = "wayland,x11,windows"; # add fallbacks so that easyanticheat and steam works
  CLUTTER_BACKEND = "wayland";
}
