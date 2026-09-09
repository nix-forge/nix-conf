{
  nixos = _: {
    # The upstream module installs ykman, enables pcscd with CCID drivers,
    # and supplies Yubico's udev rules for unprivileged USB access.
    programs.yubikey-manager.enable = true;
  };

  darwin = { pkgs, ... }: {
    # macOS supplies PC/SC and USB HID access. Only the management CLI is
    # needed here; it supports FIDO, OATH, PIV, and OpenPGP applications.
    environment.systemPackages = [ pkgs.yubikey-manager ];
  };
}
