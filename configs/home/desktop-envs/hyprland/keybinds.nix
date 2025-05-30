{
  config,
  pkgs,
  lib,
  ...
}:
{
  # <https://wiki.hyprland.org/Configuring/Dispatchers/>
  wayland.windowManager.hyprland.settings =
    let
      MOUSE_LMB = "mouse:272";
      MOUSE_RMB = "mouse:273";
      # MOUSE_MMB = "mouse:274";
      MOUSE_EX1 = "mouse:275";
      MOUSE_EX2 = "mouse:276";

      # Clipboard Manager Setup
      wl-paste-bin = "${pkgs.wl-clipboard}/bin/wl-paste";
      wl-copy-bin = "${pkgs.wl-clipboard}/bin/wl-copy";
      imagemagick-convert-bin = "${pkgs.imagemagick}/bin/convert";

      # Collections of keybinds common across multiple submaps are collected into
      # groups, which can be merged together granularly.
      groups = {
        # Self-explanatory.
        launchPrograms.bind = [
          # Launch the program with a shortcut.
          "SUPER, E, exec, ${lib.getExe pkgs.nautilus}"
          "SUPER, Return, exec, ${config.home.sessionVariables.TERMINAL}"

          # Calulator
          # There is a Calculator and a Calculater. Don't ask me why.
          "SUPER, C, exec, ${lib.getExe pkgs.qalculate-gtk}"
          ", XF86Calculator, exec, ${lib.getExe pkgs.qalculate-gtk}"
          ", XF86Calculater, exec, ${lib.getExe pkgs.qalculate-gtk}"
        ];

        # Screen by window drag
        screenshot.bind =
          let
            fullScreenshot = "${lib.getExe pkgs.grim} -t png";
            windowScreenshot = "${lib.getExe pkgs.grim} -t png -g \"$(${lib.getExe pkgs.slurp})\" - | ${imagemagick-convert-bin} - -shave 1x1 PNG:-";
            windowScreenshotOCR = "${windowScreenshot} | ${lib.getExe pkgs.tesseract} stdin stdout | ${wl-copy-bin}";
            fullScreenshotCopy = "${fullScreenshot} | ${wl-copy-bin}";
            windowScreenshotCopy = "${windowScreenshot} | ${wl-copy-bin}";
          in
          [
            ", Print, exec, ${fullScreenshotCopy}"
            "SUPER_SHIFT, S, exec, ${windowScreenshotCopy}"
            "SUPER_SHIFT, T, exec, ${windowScreenshotOCR}"
          ];

        # Kill the active window.
        killWindow.bind = [ "SUPER, Q, killactive," ];

        # Either window focus or window movement.
        moveFocusOrWindow = lib.mkMerge [
          groups.moveFocus
          groups.moveWindow
          groups.mouseMoveWindow
        ];

        # Focus on another window, in the specified direction.
        moveFocus.bind = [
          "SUPER, left, movefocus, l"
          "SUPER, right, movefocus, r"
          "SUPER, up, movefocus, u"
          "SUPER, down, movefocus, d"
        ];

        # Swap the active window with another, in the specified direction.
        moveWindow.bind = [
          "SUPER_SHIFT, left, movewindow, l"
          "SUPER_SHIFT, right, movewindow, r"
          "SUPER_SHIFT, up, movewindow, u"
          "SUPER_SHIFT, down, movewindow, d"
        ];

        # Translate the dragged window by mouse movement.
        mouseMoveWindow.bindm = [ "SUPER, ${MOUSE_LMB}, movewindow" ];

        # Toggle between vertical and horizontal split for
        # the active window and an adjacent one.
        toggleSplit.bind = [ "SUPER, tab, togglesplit," ];

        # Resize a window with the mouse.
        mouseResizeWindow.bindm = [ "SUPER, ${MOUSE_RMB}, resizewindow" ];

        # Switch to the next/previous tab in the active group.
        changeGroupActive.bind = [
          "ALT, tab, changegroupactive, f"
          "ALT, grave, changegroupactive, b"
        ];

        # Switch to another workspace.
        switchWorkspace = lib.mkMerge [
          groups.switchWorkspaceAbsolute
          groups.switchWorkspaceRelative
        ];

        # Switch to a workspace by absolute identifier.
        switchWorkspaceAbsolute.bind = [
          # Switch to a primary workspace by index.
          "SUPER, 1, workspace, 1"
          "SUPER, 2, workspace, 2"
          "SUPER, 3, workspace, 3"
          "SUPER, 4, workspace, 4"
          "SUPER, 5, workspace, 5"
          "SUPER, 6, workspace, 6"
          "SUPER, 7, workspace, 7"
          "SUPER, 8, workspace, 8"
          "SUPER, 9, workspace, 9"
          "SUPER, 0, workspace, 10"

          # Switch to an alternate workspace by index.
          "SUPER_ALT, 1, workspace, 11"
          "SUPER_ALT, 2, workspace, 12"
          "SUPER_ALT, 3, workspace, 13"
          "SUPER_ALT, 4, workspace, 14"
          "SUPER_ALT, 5, workspace, 15"
          "SUPER_ALT, 6, workspace, 16"
          "SUPER_ALT, 7, workspace, 17"
          "SUPER_ALT, 8, workspace, 18"
          "SUPER_ALT, 9, workspace, 19"
          "SUPER_ALT, 0, workspace, 20"

          # TODO Bind the special workspace to `XF86Favorites`.
          # TODO Create a bind for "insert after current workspace".
        ];

        # Switch to workspaces relative to the current one.
        switchWorkspaceRelative.bind = [
          # Switch to the next/previous used workspace with page keys.
          "SUPER, page_down, workspace, m+1"
          "SUPER, page_up, workspace, m-1"

          # Switch to the next/previous used workspace
          # with the right and left square brackets,
          # while holding super and shift.
          "SUPER, bracketright, workspace, m+1"
          "SUPER, bracketleft, workspace, m-1"

          # Switch to the next/previous used workspace with the mouse wheel.
          "SUPER, mouse_up, workspace, m+1"
          "SUPER, mouse_down, workspace, m-1"
        ];

        # Send a window to another workspace.
        sendWindow = lib.mkMerge [
          groups.sendWindowAbsolute
          groups.sendWindowRelative
        ];

        # Send a window to a workspace by absolute identifier.
        sendWindowAbsolute.bind = [
          # Move the active window or group to a primary workspace by index.
          "SUPER_SHIFT, 1, movetoworkspacesilent, 1"
          "SUPER_SHIFT, 2, movetoworkspacesilent, 2"
          "SUPER_SHIFT, 3, movetoworkspacesilent, 3"
          "SUPER_SHIFT, 4, movetoworkspacesilent, 4"
          "SUPER_SHIFT, 5, movetoworkspacesilent, 5"
          "SUPER_SHIFT, 6, movetoworkspacesilent, 6"
          "SUPER_SHIFT, 7, movetoworkspacesilent, 7"
          "SUPER_SHIFT, 8, movetoworkspacesilent, 8"
          "SUPER_SHIFT, 9, movetoworkspacesilent, 9"
          "SUPER_SHIFT, 0, movetoworkspacesilent, 10"

          # Move the active window or group to an alternate workspace by index.
          "SUPER_ALT_SHIFT, 1, movetoworkspacesilent, 11"
          "SUPER_ALT_SHIFT, 2, movetoworkspacesilent, 12"
          "SUPER_ALT_SHIFT, 3, movetoworkspacesilent, 13"
          "SUPER_ALT_SHIFT, 4, movetoworkspacesilent, 14"
          "SUPER_ALT_SHIFT, 5, movetoworkspacesilent, 15"
          "SUPER_ALT_SHIFT, 6, movetoworkspacesilent, 16"
          "SUPER_ALT_SHIFT, 7, movetoworkspacesilent, 17"
          "SUPER_ALT_SHIFT, 8, movetoworkspacesilent, 18"
          "SUPER_ALT_SHIFT, 9, movetoworkspacesilent, 19"
          "SUPER_ALT_SHIFT, 0, movetoworkspacesilent, 20"
        ];

        # Send windows to other workspaces, relative to the current one.
        sendWindowRelative.bind = [
          # Move the active window or group to the next/previous
          # workspace with page keys, while holding super and shift.
          "SUPER_SHIFT, page_down, movetoworkspace, r+1"
          "SUPER_SHIFT, page_up, movetoworkspace, r-1"

          # Move the active window or group to the next/previous
          # workspace with the right and left square brackets,
          # while holding super and shift.
          "SUPER_SHIFT, bracketright, movetoworkspace, r+1"
          "SUPER_SHIFT, bracketleft, movetoworkspace, r-1"

          # Move the active window or group to the next/previous
          # workspace with the mouse wheel while holding super and shift.
          "SUPER_SHIFT, mouse_up, movetoworkspace, r+1"
          "SUPER_SHIFT, mouse_down, movetoworkspace, r-1"
        ];
      };
    in
    lib.mkMerge [
      ### CLIPBOARD MANAGER ###

      ### ACTIVE WINDOW ACTIONS ###
      groups.killWindow
      {
        bind = [
          # Toggle full-screen for the active window.
          "SUPER_SHIFT, F, fullscreen, 0"

          # Float/unfloat the active window.
          "SUPER, F, togglefloating,"
        ];
      }
      ### MISCELLANEOUS ###
      groups.screenshot
      {
        bind = [
          # Lock the session immediately.
          # "SUPER, l, exec, loginctl lock-session"

          # Kill the window manager.
          "SUPER_SHIFT, M, exit,"

          # Forcefully kill a program after selecting its window with the mouse.
          "SUPER_SHIFT, Q, exec, hyprctl kill"

          # Screenshot the currently focused window and copy to clipboard.
          # "SUPER, print, exec, ${exec.screenshotWindow}";

          # Select a region and take a screenshot, saving to the clipboard.
          # "SUPER_SHIFT, print, exec, prtsc -c -m r -D -b 00000066";

          # Open Rofi to select an emoji to copy to clipboard.
          # "SUPER, equal, exec, rofi -show emoji -emoji-mode copy";

          # Bypass all binds for the window manager and pass key combinations
          # directly to the active window.
          # "SUPER_SHIFT, K, submap, passthru";
          # submap.passthru = {
          #   "SUPER_SHIFT, K, submap, reset";
          # };
        ];
      }
      ### PROGRAM LAUNCHING ###
      groups.launchPrograms
      {
        bind = [
          # Open Rofi to launch a program
          "SUPER, Space, exec, ${lib.getExe config.programs.rofi.finalPackage} -show drun -show-icons"
        ];
      }
      ### FUNCTION KEYS ###
      {
        # The names of these keys can be found at:
        # <https://github.com/xkbcommon/libxkbcommon/blob/master/include/xkbcommon/xkbcommon-keysyms.h>
        bindel = [
          # Raise and lower the volume of the active audio output.
          ", XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
          ", XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"

          # Raise and lower display brightness.
          ", XF86MonBrightnessUp, exec, ${lib.getExe pkgs.brightnessctl} set +10%"
          ", XF86MonBrightnessDown, exec, ${lib.getExe pkgs.brightnessctl} set 10%-"
        ];

        bindl = [
          # Mute/unmute the active audio output.
          ", XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"

          # Regular media control keys, if your laptop or bluetooth device has them.
          ", XF86AudioPlay, exec, ${lib.getExe pkgs.playerctl} play-pause"
          ", XF86AudioPrev, exec, ${lib.getExe pkgs.playerctl} previous"
          ", XF86AudioNext, exec, ${lib.getExe pkgs.playerctl} next"

          # Poor-man's media player control keys.
          "SUPER, slash, exec, ${lib.getExe pkgs.playerctl} play-pause"
          "SUPER, comma, exec, ${lib.getExe pkgs.playerctl} previous"
          "SUPER, period, exec, ${lib.getExe pkgs.playerctl} next"
        ];
      }
      ### WINDOW FOCUS & MOVEMENT ###
      groups.moveFocusOrWindow
      ### WINDOW RESIZING ###
      # groups.toggleSplit
      groups.mouseResizeWindow
      ### WORKSPACE SWITCHING ###
      groups.switchWorkspace
      ### WORKSPACE WINDOW MOVEMENT ###
      groups.sendWindow
    ];
}
