{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  programs.mpv = {
    enable = true;

    scripts = [
      pkgs.mpvScripts.uosc
      pkgs.mpvScripts.thumbfast
    ]
    ++ lib.optionals isLinux [ pkgs.mpvScripts.mpris ];

    config = {
      hwdec = "auto";
      deband = true;
      "osd-bar" = false;
      "screenshot-format" = "png";
      "autofit-larger" = "100%x100%";
    };

    bindings = { };
  };
}
