{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  cfg = config.programs.tmux.declarative;
  boolToTmux = value: if value then "on" else "off";

  terminalFeatureLines = lib.mapAttrsToList (
    terminal: features:
    "set -as terminal-features \",${terminal}:${lib.concatStringsSep ":" features}\""
  ) cfg.terminalFeatures;

  renderedConfig = lib.concatStringsSep "\n" (
    terminalFeatureLines
    ++ [
      "set -s set-clipboard ${cfg.clipboard}"
      "set -g allow-passthrough ${boolToTmux cfg.allowPassthrough}"
      "set -g renumber-windows ${boolToTmux cfg.renumberWindows}"
      "set -g detach-on-destroy ${boolToTmux cfg.detachOnDestroy}"
      "set -g set-titles ${boolToTmux cfg.setTitles}"
      "set -g set-titles-string \"${cfg.titleFormat}\""
      "set -g status-position ${cfg.status.position}"
      "set -g status-interval ${toString cfg.status.interval}"
      "set -g status-left-length ${toString cfg.status.leftLength}"
      "set -g status-right-length ${toString cfg.status.rightLength}"
      "set -g status-left \"${cfg.status.leftFormat}\""
      "set -g window-status-format \"${cfg.status.windowFormat}\""
      "set -g window-status-current-format \"${cfg.status.currentWindowFormat}\""
      "set -g window-status-separator \"${cfg.status.windowSeparator}\""
      "set -g status-right \"${cfg.status.rightFormat}\""
      "bind-key ${cfg.bindings.horizontalSplit} split-window -h -c \"#{pane_current_path}\""
      "bind-key ${cfg.bindings.verticalSplit} split-window -v -c \"#{pane_current_path}\""
      "bind-key ${cfg.bindings.newWindow} new-window -c \"#{pane_current_path}\""
      "bind-key -T copy-mode-vi ${cfg.copyMode.beginSelection} send-keys -X begin-selection"
      "bind-key -T copy-mode-vi ${cfg.copyMode.copySelection} send-keys -X copy-selection-and-cancel"
      "bind-key -T copy-mode-vi ${cfg.copyMode.cancel} send-keys -X cancel"
    ]
  );
in
{
  options.programs.tmux.declarative = {
    terminalFeatures = mkOption {
      type = types.attrsOf (types.listOf types.str);
      description = "Terminal capabilities that tmux should enable for known outer terminals.";
    };

    clipboard = mkOption {
      type = types.enum [
        "off"
        "external"
        "on"
      ];
      description = "tmux OSC 52 clipboard policy.";
    };

    allowPassthrough = mkOption {
      type = types.bool;
      description = "Whether pane programs may bypass tmux with passthrough sequences.";
    };

    renumberWindows = mkOption {
      type = types.bool;
      description = "Renumber windows after one closes.";
    };

    detachOnDestroy = mkOption {
      type = types.bool;
      description = "Detach clients when their current session is destroyed.";
    };

    setTitles = mkOption {
      type = types.bool;
      description = "Update the outer terminal title from tmux.";
    };

    titleFormat = mkOption {
      type = types.str;
      description = "Format for the outer terminal title.";
    };

    status = {
      position = mkOption {
        type = types.enum [
          "top"
          "bottom"
        ];
        description = "Status line position.";
      };
      interval = mkOption {
        type = types.ints.positive;
        description = "Seconds between native status line refreshes.";
      };
      leftLength = mkOption {
        type = types.ints.positive;
        description = "Maximum status-left width.";
      };
      rightLength = mkOption {
        type = types.ints.positive;
        description = "Maximum status-right width.";
      };
      leftFormat = mkOption {
        type = types.str;
        description = "Native status-left format.";
      };
      windowFormat = mkOption {
        type = types.str;
        description = "Format for inactive windows in the status line.";
      };
      currentWindowFormat = mkOption {
        type = types.str;
        description = "Format for the active window in the status line.";
      };
      windowSeparator = mkOption {
        type = types.str;
        description = "Separator between window entries.";
      };
      rightFormat = mkOption {
        type = types.str;
        description = "Native status-right format.";
      };
    };

    bindings = {
      horizontalSplit = mkOption {
        type = types.str;
        description = "Key for a horizontal split in the active pane directory.";
      };
      verticalSplit = mkOption {
        type = types.str;
        description = "Key for a vertical split in the active pane directory.";
      };
      newWindow = mkOption {
        type = types.str;
        description = "Key for a new window in the active pane directory.";
      };
    };

    copyMode = {
      beginSelection = mkOption {
        type = types.str;
        description = "Vi copy-mode key that starts a selection.";
      };
      copySelection = mkOption {
        type = types.str;
        description = "Vi copy-mode key that copies and exits.";
      };
      cancel = mkOption {
        type = types.str;
        description = "Vi copy-mode key that cancels.";
      };
    };
  };

  config = {
    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      keyMode = "vi";
      customPaneNavigationAndResize = true;
      resizeAmount = 10;
      mouse = true;
      focusEvents = true;
      historyLimit = 50000;
      escapeTime = 10;
      baseIndex = 1;
      clock24 = true;
      secureSocket = isLinux;

      # The generated text comes exclusively from the typed options above.
      # `mkAfter` keeps Stylix's generated theme import ahead of these values.
      extraConfig = lib.mkAfter renderedConfig;
    };

    programs.tmux.declarative = {
      # Ghostty uses xterm-ghostty and exposes true color, OSC 52, focus,
      # titles, and OSC 8 links. tmux-256color covers nested tmux. The SSH
      # fallback is xterm-256color, so it receives no unsafe feature claims.
      terminalFeatures = {
        "xterm-ghostty" = [
          "RGB"
          "clipboard"
          "focus"
          "title"
          "hyperlinks"
        ];
        "tmux-256color" = [
          "RGB"
          "clipboard"
          "focus"
          "title"
          "hyperlinks"
        ];
      };

      # `external` lets tmux copy through Ghostty without allowing arbitrary
      # pane programs to write the clipboard via OSC 52.
      clipboard = "external";
      allowPassthrough = false;
      renumberWindows = true;
      detachOnDestroy = false;
      setTitles = true;
      titleFormat = "#S: #W";

      status = {
        position = "bottom";
        interval = 5;
        leftLength = 32;
        rightLength = 64;
        leftFormat = "#[bold] #S #[default]";
        windowFormat = " #I:#W ";
        currentWindowFormat = "#[bold] #I:#W ";
        windowSeparator = "";
        rightFormat = "#{?window_zoomed_flag,[Z] ,}#H %Y-%m-%d %H:%M ";
      };

      bindings = {
        horizontalSplit = "|";
        verticalSplit = "-";
        newWindow = "c";
      };

      copyMode = {
        beginSelection = "v";
        copySelection = "y";
        cancel = "Escape";
      };
    };
  };
}
