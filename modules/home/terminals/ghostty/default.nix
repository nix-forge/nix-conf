{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  macShortcuts = config.keyboard.macosShortcuts.enable or false;
in
{
  key = "nix-conf/ghostty/homeManager";
  config = {
    programs.ghostty = {
      enable = true;
      package = lib.mkIf isDarwin (lib.mkDefault pkgs.ghostty-bin);

      # DOCS: https://ghostty.org/docs/config/reference
      settings = {
        shell-integration = "detect";
        # Hosts that need Ghostty's terminfo declare it themselves (notably the
        # desktop).  Avoid Ghostty's per-user SSH upload helper: it can emit a
        # spurious failure even when the remote system already has the entry.
        # Keep the normal prompt, title, cursor, sudo, and PATH integration.
        shell-integration-features = "no-ssh-terminfo";
        cursor-click-to-move = true;

        scrollback-limit = 268435456;

        clipboard-read = "ask";
        clipboard-write = "allow";
        clipboard-paste-protection = true;
        clipboard-trim-trailing-spaces = true;

        # Prevent title querying (can be risky). keep it off explicitly.
        title-report = false;

        link-previews = "osc8";

        right-click-action = "copy-or-paste";

        mouse-hide-while-typing = true;

        auto-update = "off";
      }
      // lib.optionalAttrs macShortcuts {
        keybind = [
          "super+c=copy_to_clipboard"
          "super+v=paste_from_clipboard"
          "super+a=select_all"
          "super+f=start_search"
          "super+t=new_tab"
          "super+n=new_window"
          "super+w=close_tab:this"
          "super+shift+w=close_window"
          "super+q=quit"
          "super+equal=increase_font_size:1"
          "super+shift+equal=increase_font_size:1"
          "super+minus=decrease_font_size:1"
          "super+0=reset_font_size"
          "super+shift+bracket_left=previous_tab"
          "super+shift+bracket_right=next_tab"
          "super+arrow_left=text:\\x01"
          "super+arrow_right=text:\\x05"
          "super+arrow_up=scroll_to_top"
          "super+arrow_down=scroll_to_bottom"
          "alt+arrow_left=esc:b"
          "alt+arrow_right=esc:f"
          "alt+backspace=text:\\x17"
          "super+backspace=text:\\x15"
        ]
        ++ map (n: "super+${toString n}=goto_tab:${toString n}") (lib.range 1 9);
      }
      // lib.optionalAttrs isDarwin {
        # Treat Option as Alt (recommended if you use terminal apps that rely on Alt bindings)
        macos-option-as-alt = true;

        # macOS secure input: auto-enable on detected password prompts + show indication
        macos-auto-secure-input = true;
        macos-secure-input-indication = true;

        # macOS app convention: keep app running after last window closed
        quit-after-last-window-closed = false;

        # Rendering safety: vsync defaults true on macOS for stability reasons
        window-vsync = true;

        # Persist window/tab/split layouts between launches
        window-save-state = "always";

        # Quick terminal behavior
        quick-terminal-autohide = true;
        quick-terminal-space-behavior = "move";
        quick-terminal-animation-duration = 0.12;
      }
      // lib.optionalAttrs (isDarwin && !macShortcuts) {
        keybind = [
          # Option+Delete / Option+Backspace => Ctrl-W
          # Delete previous word in bash/zsh/nushell-style line editors.
          "option+backspace=text:\\x17"

          # Command+Delete / Command+Backspace => Ctrl-U
          # Delete from cursor to beginning of line.
          "cmd+backspace=text:\\x15"
        ];
      }
      // lib.optionalAttrs isLinux {
        # Linux convention: quit when last window closes
        quit-after-last-window-closed = true;
        quit-after-last-window-closed-delay = "2s";

        # Quick terminal defaults to staying open on Linux; keep it that way
        quick-terminal-autohide = false;

        # GTK: show working directory in the subtitle (nice for many-tab workflows)
        window-subtitle = "working-directory";

        # Linux/systemd
        linux-cgroup = "single-instance";
        linux-cgroup-hard-fail = false;

        # GTK multi-launch behavior (generally leave as detect)
        gtk-single-instance = "detect";
      };
    };
  };
}
