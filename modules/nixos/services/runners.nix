{ pkgs, ... }: {
  # Opt-in compatibility for downloaded binaries. NixOS owns the AppImage
  # interpreter registrations for both formats and the required FUSE setup.
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.nix-ld = {
    enable = true;
    # Extend NixOS's base libraries with desktop dependencies. Applications
    # needing more libraries can add them through this same upstream option.
    libraries = with pkgs; [
      glib
      glibc
      icu
      libunwind
      libsecret
      freetype
      libglvnd
      libnotify
      SDL2
      vulkan-loader
      gdk-pixbuf
      libx11
    ];
  };
}
