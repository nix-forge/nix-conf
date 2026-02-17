{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf isDarwin pkgs.ghostty-bin;

    # DOCS: https://ghostty.org/docs/config/reference
    settings = {
      shell-integration = "detect";
      shell-integration-features = true;
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
}
