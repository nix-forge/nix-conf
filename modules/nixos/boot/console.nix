{ lib, pkgs, ... }: {
  # Keep the kernel virtual terminal as the dependable recovery interface,
  # independent of a userspace compositor or DRM-seat owner. Applying the
  # declared keyboard map in the systemd-based initrd makes encrypted-root
  # prompts and early boot failures usable with the same layout as the
  # installed system. Fonts, palettes,
  # and any non-default keymap remain host-local user-experience choices.
  console = {
    earlySetup = lib.mkDefault true;
    useXkbConfig = lib.mkDefault true;

    # Stylix only themes graphical applications. Terminus is a purpose-built
    # bitmap console face, so recovery shells and early boot prompts stay
    # readable at the fixed resolution of a Linux virtual terminal.
    font = lib.mkDefault "ter-v16n";
    packages = [ pkgs.terminus_font ];
  };
}
