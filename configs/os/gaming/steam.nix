{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.platformOptimizations ];

  programs.steam = {
    enable = true;

    platformOptimizations.enable = true;

    extraCompatPackages = [ pkgs.proton-ge-bin ];

    package = pkgs.steam.override {
      extraEnv = {
        MANGOHUD = true;
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
