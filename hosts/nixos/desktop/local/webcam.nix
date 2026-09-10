{ pkgs, ... }: {
  # Native UVC capture works with Zoom and other V4L2/PipeWire applications.
  # USBGuard owns hardware trust; the physical shutter and application
  # controls provide privacy without an administrator step before calls.
  environment.systemPackages = [ pkgs.v4l-utils ];

  # Brio 101 provides 1080p30 through MJPEG; uncompressed 1080p is only 5 fps.
  # Applications own format negotiation. Keep automatic exposure and white
  # balance, but prevent exposure from reducing the requested frame rate.
  # Apply only to the capture node, not the camera's metadata node.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="video4linux", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="094d", ATTR{index}=="0", RUN+="${pkgs.v4l-utils}/bin/v4l2-ctl --device=$devnode --set-ctrl=exposure_dynamic_framerate=0"
  '';
}
