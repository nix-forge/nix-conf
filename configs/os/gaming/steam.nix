{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.platformOptimizations ];

  programs.steam = {
    enable = true;

    platformOptimizations.enable = true;

    extraCompatPackages = [ pkgs.proton-ge-bin ];

    package = pkgs.steam.override {
      extraEnv = {
        SDL_VIDEODRIVER = "wayland,x11,windows"; # add fallbacks so that easyanticheat works
      };

      extraPkgs =
        pkgs: with pkgs; [
          keyutils
          libkrb5
          libpng
          libpulseaudio
          libvorbis
          stdenv.cc.cc.lib
          atk
          libunwind

          # fix CJK fonts
          source-sans
          source-serif
          source-han-sans
          source-han-serif
        ];
    };
  };
}
