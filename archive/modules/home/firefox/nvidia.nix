{
  enableAV1 ? true,
  ...
}:
{ lib, ... }:
let
  inherit (lib.cust.firefox) toUserJS;
in
{
  programs.firefox.profiles.default.extraConfig =
    # Enable NVIDIA-specific acceleration tweaks only when this module is imported.
    lib.mkAfter (toUserJS {
      # NVIDIA VA-API Driver settings
      "media.hardware-video-decoding.force-enabled" = true;
      "media.rdd-ffmpeg.enabled" = true;
      "media.av1.enabled" = enableAV1;
      "gfx.x11-egl.force-enabled" = true;
      "widget.dmabuf.force-enabled" = true;

      # Disable accelerated canvas to work around PDF and Google Docs rendering glitches on NVIDIA.
      # NOTE: Might not be necessary with newer drivers
      "gfx.canvas.accelerated" = false;
    });
}
