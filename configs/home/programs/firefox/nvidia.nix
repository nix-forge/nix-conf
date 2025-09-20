profileName:
{ lib, ... }:
let
  inherit (lib.cust.firefox) toUserJS;
in
{
  programs.firefox.profiles.${profileName}.extraConfig =
    # Enable NVIDIA-specific acceleration tweaks only when this module is imported.
    lib.mkAfter (toUserJS {
      "gfx.webrender.all" = true;
      "media.ffmpeg.vaapi.enabled" = true;
      "media.rdd-ffmpeg.enabled" = true;
      "media.av1.enabled" = true;
      "widget.dmabuf.force-enabled" = true;
      # Disable accelerated canvas to work around PDF and Google Docs rendering glitches on NVIDIA.
      "gfx.canvas.accelerated" = false;
    });
}
