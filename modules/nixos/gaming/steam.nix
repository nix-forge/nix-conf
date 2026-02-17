{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.platformOptimizations ];

  programs.steam = {
    enable = true;

    platformOptimizations.enable = true;

    extraCompatPackages = [ pkgs.proton-ge-bin ];

    gamescopeSession.enable = true;

    package = pkgs.steam.override {
      extraPkgs =
        pkgs: with pkgs; [
          xorg.libXcursor
          xorg.libXi
          xorg.libXinerama
          xorg.libXScrnSaver
          libpng
          libpulseaudio
          libvorbis
          stdenv.cc.cc.lib
          libkrb5
          keyutils
          atk
          libunwind

          # fix CJK fonts
          source-sans
          source-serif
          source-han-sans
          source-han-serif

          # audio
          pipewire
          # other common
          udev
          alsa-lib
          vulkan-loader
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr # To use the x11 feature
          libxkbcommon
          wayland # To use the wayland feature
        ];
    };
  };
}
