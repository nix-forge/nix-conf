{ lib, pkgs, ... }: {
  # Use the unmodified upstream application. Server login is managed by its UI.
  home.packages = [ pkgs.feishin ];
  programs.mpv.enable = lib.mkDefault true;
}
