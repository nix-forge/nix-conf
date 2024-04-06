{ pkgs, lib, ... }:
###########################################################
#
# Kitty Configuration
#
# Useful Hot Keys for Linux:
#   1. New Tab: `ctrl + shift + t`
#   2. Close Tab: `ctrl + shift + q`
#   3. Switch Tab: `ctrl + shift + right` | `ctrl + shift + left`
#   4. Increase Font Size: `ctrl + shift + =` | `ctrl + shift + +`
#   5. Decrease Font Size: `ctrl + shift + -` | `ctrl + shift + _`
#   6. And Other common shortcuts such as Copy, Paste, Cursor Move, etc.
#
###########################################################
{
  programs.kitty = {
    enable = true;

    # all the built-in themes to kitty are packaged into an extra package named `kitty-themes`
    # you can view the themes here:
    # https://github.com/kovidgoyal/kitty-themes/tree/master/themes
    # these themes are installed by home-manager if the `theme` is specified
    # look at the contents of kitty-themes conf files to see theme names
    theme = "Catppuccin-Mocha";

    # Set package
    package = pkgs.kitty;

    font = {
      name = "CaskaydiaCove Nerd Font";
      size = 13;
    };

    shellIntegration.enableZshIntegration = true;
    settings.shell = "${lib.getExe pkgs.zsh} --login --interactive";

    keybindings = { "ctrl+shift+m" = "toggle_maximized"; };

    settings = {
      background_opacity = "0.93";
      scrollback_lines = 10000;
      enable_audio_bell = false;
      tab_bar_edge = "top"; # tab bar on top
    };
  };
}
