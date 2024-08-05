{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  environment.systemPackages = with pkgs; [ xwaylandvideobridge ];

  programs.xwayland.enable = true;
}
