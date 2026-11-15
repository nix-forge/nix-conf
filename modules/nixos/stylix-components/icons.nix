{ pkgs, ... }: {
  imports = [ ./base.nix ];
  stylix.icons = {
    enable = true;
    package = pkgs.papirus-icon-theme;
    dark = "Papirus-Dark";
    light = "Papirus";
  };
}
