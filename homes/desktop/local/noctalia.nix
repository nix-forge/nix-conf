{ inputs, lib, ... }: {
  imports = [ inputs.noctalia.homeModules.default ];

  # AirPods Pro 2 stem swipes move AVRCP volume by 8 on its 0..127 scale.
  # Match that measured step in the keyboard and bar controls.
  desktop.noctalia.volumeStepPercent = 100.0 * 8 / 127;

  programs.noctalia.settings = {
    # Keep app controls left and status controls right, with workspaces centered.
    # The Stylix target owns the bar's appearance.
    bar.default = {
      start = lib.mkForce [
        "session"
        "active_window"
      ];
      center = lib.mkForce [ "taskbar" ];
      end = lib.mkForce [
        "tray"
        "now-playing"
        "volume"
        "bluetooth"
        "battery"
        "network"
        "launcher"
        "control-center"
        "privacy"
        "clock"
      ];
    };

    widget = {
      # Native workspace groups retain window identity, focus actions and tooltips.
      # Keep every window visible, including multiple windows of the same app.
      taskbar = {
        group_by_workspace = true;
        workspace_group_content = "icons";
        group_single_icon_per_app = false;
        workspace_group_capsule = true;
        show_workspace_label = true;
        workspace_label_placement = "inside";
        # Plain labels avoid nested badges; reserve the theme accent for selection.
        minimal = true;
        hide_empty_workspaces = false;
        only_active_workspace = false;
        show_all_outputs = false;
        show_active_indicator = false;
        # Workspace windows use application artwork from the configured theme.
        # Symbolic status variants can look unlike the app, notably Ghostty.
        symbolic_icons = lib.mkForce false;
      };
      active_window = {
        display = "text_only";
        min_length = 0;
        max_length = 300;
      };
      # Keep playback one click away without album art or a scrolling song title.
      now-playing = {
        type = "launcher";
        glyph = "player-play";
        actions = {
          left = "panel-toggle control-center media";
          right = "media toggle";
        };
      };
      volume.show_label = false;
      launcher.glyph = "search";
      control-center.glyph = "adjustments-horizontal";
      clock.actions = {
        left = "panel-toggle control-center notifications";
        right = "panel-toggle control-center calendar";
      };
    };
  };
}
