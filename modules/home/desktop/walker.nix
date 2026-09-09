{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  desktopLib = myLib.desktop;
  cfg = config.desktop.walker;
  defaultSettings = {
    force_keyboard_focus = true;
    close_when_open = true;
    click_to_close = true;
    selection_wrap = true;
    hide_action_hints = true;
    hide_action_hints_dmenu = true;
    hide_quick_activation = true;
    resume_last_query = false;
    shell = {
      anchor_top = true;
      anchor_bottom = true;
      anchor_left = true;
      anchor_right = true;
    };
    placeholders = {
      default = {
        input = "Search apps, calculate, or use a prefix";
        list = "No matching results";
      };
      desktopapplications = {
        input = "Launch application";
        list = "No applications found";
      };
      files = {
        input = "Find file";
        list = "No files found";
      };
      runner = {
        input = "Run command";
        list = "No commands found";
      };
    };
    keybinds = {
      close = [ "Escape" ];
      next = [
        "Down"
        "ctrl j"
      ];
      previous = [
        "Up"
        "ctrl k"
      ];
    };
    providers = {
      default = [
        "desktopapplications"
        "calc"
      ];
      empty = [ "desktopapplications" ];
      max_results = 36;
      max_results_provider = {
        desktopapplications = 24;
        calc = 6;
        files = 24;
        runner = 12;
        clipboard = 20;
      };
      prefixes = [
        {
          prefix = ";";
          provider = "providerlist";
        }
        {
          prefix = "/";
          provider = "files";
        }
        {
          prefix = ">";
          provider = "runner";
        }
        {
          prefix = "=";
          provider = "calc";
        }
        {
          prefix = ":";
          provider = "clipboard";
        }
        {
          prefix = ".";
          provider = "symbols";
        }
      ];
    };
  };
in
{
  options.desktop.walker = {
    enable = lib.mkEnableOption "Walker with the desktop theme and generated TOML settings";
    settings = lib.mkOption {
      inherit (pkgs.formats.toml { }) type;
      default = { };
      description = ''
        Walker settings rendered as TOML. Walker does not publish a configuration
        schema, so the build checks TOML generation only. Walker interprets these
        settings when loading the configuration.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    desktop.walker.settings = lib.mapAttrsRecursive (_: lib.mkDefault) defaultSettings;
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "desktop.walker is supported on Linux only.";
      }
    ];
    home.packages = [ pkgs.walker ];
    xdg.configFile."walker/config.toml".source = desktopLib.mkWalkerConfig {
      inherit pkgs;
      inherit (cfg) settings;
    };

  };
}
