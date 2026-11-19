{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.keyboard.macosShortcuts;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  # Firmware supplies Alt at Option and Super at Command. Never swap them here.
  appRule = name: applications: remap: {
    inherit name remap;
    application.only = applications;
    exact_match = true;
  };
  common = {
    Super-c = "Ctrl-c";
    Super-v = "Ctrl-v";
    Super-x = "Ctrl-x";
    Super-a = "Ctrl-a";
    Super-s = "Ctrl-s";
    Super-f = "Ctrl-f";
    Super-z = "Ctrl-z";
    Super-Shift-z = "Ctrl-Shift-z";
    Super-Shift-s = "Ctrl-Shift-s";
    Super-n = "Ctrl-n";
    Super-o = "Ctrl-o";
    Super-p = "Ctrl-p";
    Super-w = "Ctrl-w";
    Super-Left = "Home";
    Super-Right = "End";
    Super-Up = "Ctrl-Home";
    Super-Down = "Ctrl-End";
    Super-Shift-Left = "Shift-Home";
    Super-Shift-Right = "Shift-End";
    Super-Shift-Up = "Ctrl-Shift-Home";
    Super-Shift-Down = "Ctrl-Shift-End";
    Alt-Left = "Ctrl-Left";
    Alt-Right = "Ctrl-Right";
    Alt-Shift-Left = "Ctrl-Shift-Left";
    Alt-Shift-Right = "Ctrl-Shift-Right";
    Alt-BackSpace = "Ctrl-BackSpace";
    Alt-Delete = "Ctrl-Delete";
    # Select only the text before the caret, then delete that selection.
    Super-BackSpace = [
      "Shift-Home"
      "BackSpace"
    ];
  };
  browsers = [
    "firefox"
    "zen"
    "zen-beta"
    "zen-twilight"
    "google-chrome"
    "chromium"
    "helium"
  ];
  rules = {
    keymap = [
      (appRule "Browser commands" browsers (
        common
        // {
          Super-l = "Ctrl-l";
          Super-t = "Ctrl-t";
          Super-Shift-t = "Ctrl-Shift-t";
          Super-r = "Ctrl-r";
          Super-Shift-r = "Ctrl-Shift-r";
          Super-g = "Ctrl-g";
          Super-Shift-g = "Ctrl-Shift-g";
          Super-LeftBrace = "Alt-Left";
          Super-RightBrace = "Alt-Right";
          Super-Shift-LeftBrace = "Ctrl-PageUp";
          Super-Shift-RightBrace = "Ctrl-PageDown";
          Super-equal = "Ctrl-equal";
          Super-minus = "Ctrl-minus";
          Super-0 = "Ctrl-0";
        }
        // builtins.listToAttrs (
          map (n: {
            name = "Super-${toString n}";
            value = "Ctrl-${toString n}";
          }) (lib.range 1 9)
        )
      ))
      (appRule "Nautilus commands" [ "org.gnome.Nautilus" ] {
        Super-c = "Ctrl-c";
        Super-v = "Ctrl-v";
        Super-x = "Ctrl-x";
        Super-a = "Ctrl-a";
        Super-f = "Ctrl-f";
        Super-l = "Ctrl-l";
        Super-t = "Ctrl-t";
        Super-n = "Ctrl-n";
        Super-w = "Ctrl-w";
        Super-z = "Ctrl-z";
        Super-Shift-z = "Ctrl-Shift-z";
        Super-Shift-n = "Ctrl-Shift-n";
        Super-BackSpace = "Delete";
        Super-LeftBrace = "Alt-Left";
        Super-RightBrace = "Alt-Right";
        Super-Up = "Alt-Up";
        Super-Down = "Enter";
      })
      # Terminals, IDEs with embedded terminals, guests, games and unknown apps
      # deliberately have no generic fallback. Native bindings handle the IDEs.
      (appRule "Messaging text editing" [ "Signal" "signal" "discord" ] (
        lib.getAttrs [
          "Super-c"
          "Super-v"
          "Super-x"
          "Super-a"
          "Super-z"
          "Super-Shift-z"
          "Super-Left"
          "Super-Right"
          "Super-Up"
          "Super-Down"
          "Super-Shift-Left"
          "Super-Shift-Right"
          "Super-Shift-Up"
          "Super-Shift-Down"
          "Alt-Left"
          "Alt-Right"
          "Alt-Shift-Left"
          "Alt-Shift-Right"
          "Alt-BackSpace"
          "Alt-Delete"
          "Super-BackSpace"
        ] common
      ))
    ];
  };
  rulesFile = (pkgs.formats.yaml { }).generate "macos-shortcuts.yaml" rules;
in
{
  options.keyboard.macosShortcuts = {
    enable = lib.mkEnableOption "macOS-style shortcut roles with separate Command and Control";
    deviceNames = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      default = [ "Wooting Wooting 80HE" ];
      description = "Names, substrings or device paths of keyboards to remap on Linux. Firmware must already provide Mac modifier placement.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Native application modules consume the same feature flag on both OSes.
      assertions = lib.optionals isLinux [
        {
          assertion = config.wayland.windowManager.hyprland.enable;
          message = "keyboard.macosShortcuts requires Hyprland on Linux for application-aware remapping.";
        }
      ];
    })
    (lib.mkIf (cfg.enable && isLinux) {
      home.packages = [ pkgs.xremap.hyprland ];
      xdg.configFile."xremap/macos-shortcuts.yaml".source = rulesFile;
      systemd.user.services.macos-shortcuts = {
        Unit = {
          Description = "Mac-style GUI shortcuts on the work keyboard";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = lib.escapeShellArgs (
            [
              (lib.getExe pkgs.xremap.hyprland)
              "--desktop"
              "hypr"
              "--watch=device"
              "--no-window-logging"
              "--allow-launch=false"
              "--ignore"
              "Wooting Wooting 80HE System Control"
              "--ignore"
              "Wooting Wooting 80HE Consumer Control"
              "--ignore"
              "Wooting Wooting 80HE Mouse"
            ]
            ++ lib.concatMap (name: [
              "--device"
              name
            ]) cfg.deviceNames
            ++ [ rulesFile ]
          );
          Restart = "on-failure";
          RestartSec = 2;
          NoNewPrivileges = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
          ];
          UMask = "0077";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ];
}
