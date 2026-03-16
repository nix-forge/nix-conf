{ pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  programs.tmux = {
    enable = true;
    sensibleOnTop = false;
    terminal = "tmux-256color";
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    resizeAmount = 10;
    mouse = true;
    focusEvents = true;
    historyLimit = 100000;
    escapeTime = 10;
    baseIndex = 1;
    clock24 = true;
    secureSocket = isLinux;

    extraConfig = ''
      set -g set-clipboard external
      set -g allow-passthrough on
      set -as terminal-features ",xterm-256color:RGB,clipboard"
      set -as terminal-features ",xterm-ghostty:RGB,clipboard"

      bind-key | split-window -h -c "#{pane_current_path}"
      bind-key - split-window -v -c "#{pane_current_path}"
      bind-key c new-window -c "#{pane_current_path}"
      bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "tmux config reloaded"

      set -g renumber-windows on
      set -g detach-on-destroy off
      set -g status-position bottom
      set -g status-interval 5
      set -g status-left-length 32
      set -g status-right-length 64
      set -g status-style "fg=colour252,bg=colour235"
      set -g status-left "#[bold] #S #[default]"
      set -g window-status-format " #I:#W "
      set -g window-status-current-format "#[bold] #I:#W "
      set -g window-status-separator ""
      set -g status-right "#{?window_zoomed_flag,[Z] ,}#H %Y-%m-%d %H:%M "

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi Escape send-keys -X cancel
    '';
  };
}
