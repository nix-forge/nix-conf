{
  # The installed NixOS desktop owns portal packages and D-Bus activation.
  # This Home Manager layer verifies that ownership and remains useful for a
  # future standalone Linux recovery profile without affecting macOS.
  xdg.portalHomeIntegration.enable = true;
}
