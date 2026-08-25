{ lib, pkgs, ... }:
let
  fuzzel = lib.getExe pkgs.fuzzel;
in
{
  # This host deliberately supplies a complete launcher palette and font.
  # Disable Stylix's fuzzel target so it cannot redefine those same settings.
  stylix.targets.fuzzel.enable = false;

  # Fuzzel is a small, wlroots-native application launcher. It performs
  # desktop-entry search without an auxiliary daemon, which makes it the most
  # reliable low-overhead launcher for this headless Hyprland desktop.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "MonaspiceNe Nerd Font:size=14";
        terminal = "${lib.getExe pkgs.ghostty} -e";
        prompt = "Apps> ";
        placeholder = "Search applications and commands";
        "icons-enabled" = true;
        fields = "name,generic,keywords,comment,exec";
        "match-mode" = "fzf";
        "show-actions" = true;
        "list-executables-in-path" = true;
        "match-counter" = true;
        width = 55;
        lines = 10;
        "horizontal-pad" = 18;
        "vertical-pad" = 12;
        "inner-pad" = 8;
        layer = "overlay";
      };

      border = {
        width = 2;
        radius = 0;
      };

      colors = {
        background = "242424f2";
        text = "dededeff";
        prompt = "5aaee6ff";
        placeholder = "dedede99";
        input = "ffffffff";
        match = "5aaee6ff";
        selection = "0e5a94ff";
        "selection-text" = "ffffffff";
        "selection-match" = "ffffffff";
        counter = "dedede99";
        border = "0e5a94ff";
      };
    };
  };

  # SUPER+SPACE is the familiar Hyprland binding. macOS reserves Command+Space
  # for Spotlight before Moonlight can send it, so retain SUPER+Return as an
  # equally convenient remote-safe alternate for the MacBook keyboard.
  wayland.windowManager.hyprland.settings.bind = [
    {
      _args = [
        "SUPER + SPACE"
        (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON fuzzel})")
      ];
    }
    {
      _args = [
        "SUPER + RETURN"
        (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON fuzzel})")
      ];
    }
  ];
}
