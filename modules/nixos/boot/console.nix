{ lib, ... }: {
  # Keep the kernel virtual terminal as the dependable recovery interface,
  # independent of a userspace compositor or DRM-seat owner. Applying the
  # declared keyboard map in the systemd-based initrd makes encrypted-root
  # prompts and early boot failures usable with the same layout as the
  # installed system. Fonts, palettes,
  # and any non-default keymap remain host-local user-experience choices.
  console = {
    earlySetup = lib.mkDefault true;
    useXkbConfig = lib.mkDefault true;
  };
}
