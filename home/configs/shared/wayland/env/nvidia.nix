{
  home.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm"; # If you encounter crashes in Firefox then remove this line
    __GLX_VENDOR_LIBRARY_NAME = "nvidia"; # If you face problems with Discord windows not displaying or screen sharing not working in Zoom then remove this line
    WLR_NO_HARDWARE_CURSORS = "1"; # TODO: this doesn't seem to work as it needs to be set at the host level (could be wrong need to re-test)
  };
}
