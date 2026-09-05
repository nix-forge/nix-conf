{ lib, pkgs, ... }:
let
  # Atuin fixed the duplicate Nushell keybinding names in 18.20.1. Retain a
  # compatibility shim only for older packages, then automatically return to
  # Home Manager's upstream integration when the packaged fix is available.
  needsNushellIntegrationShim = lib.versionOlder pkgs.atuin.version "18.20.1";

  atuinNushellConfig =
    pkgs.runCommand "atuin-nushell-config.nu" { nativeBuildInputs = [ pkgs.gawk ]; }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/.config"
        export XDG_DATA_HOME="$HOME/.local/share"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

        ${lib.getExe pkgs.atuin} init nu | ${lib.getExe pkgs.gawk} '
          /^[[:space:]]*name: atuin$/ {
            count += 1
            if (count == 1) sub(/atuin$/, "atuin_search")
            else if (count == 2) sub(/atuin$/, "atuin_up")
          }
          { print }
          END {
            if (count != 2) {
              print "expected exactly two Atuin Nushell bindings, found " count > "/dev/stderr"
              exit 1
            }
          }
        ' > "$out"
      '';
in
{
  programs.atuin = {
    enable = true;
    daemon.enable = true;
    enableNushellIntegration = !needsNushellIntegrationShim;

    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      update_check = false;

      search_mode = "fuzzy";
      search_mode_shell_up_key_binding = "fuzzy";
      filter_mode = "global";
      filter_mode_shell_up_key_binding = "directory";
      workspaces = true;

      style = "compact";
      inline_height = 40;
      inline_height_shell_up_key_binding = 20;
      show_preview = true;
      max_preview_height = 6;
      show_help = true;
      show_tabs = true;
      auto_hide_height = 8;

      # Selecting history inserts it for review. This avoids accidentally
      # executing a destructive command because Enter had two meanings.
      enter_accept = false;
      command_chaining = true;
      exit_mode = "return-original";
      keymap_mode = "auto";
      keymap_cursor = {
        emacs = "steady-bar";
        vim_insert = "steady-bar";
        vim_normal = "steady-block";
      };

      strip_trailing_whitespace = true;
      secrets_filter = true;
      store_failed = true;
      history_filter = [
        # Drop navigation and display noise from both local and synced history.
        "^(cd|clear|exit|history|l|la|ll|lla|lt|lg|ls|pwd)([[:space:]].*)?$"
        # The built-in detector catches known token shapes. These patterns also
        # reject common assignments and CLI flags before their values leave the
        # machine, including credentials with an unfamiliar format.
        "(?i)(^|[[:space:]])(export[[:space:]]+)?[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY)[A-Z0-9_]*="
        "(?i)(^|[[:space:]])--?(password|passwd|token|secret|api[-_]?key)(=|[[:space:]])[^[:space:]]+"
      ];

      network_connect_timeout = 5;
      network_timeout = 15;

      search = {
        filters = [
          "global"
          "host"
          "session"
          "workspace"
          "directory"
          "session-preload"
        ];
        shells = "auto";
      };

      ui = {
        columns = [
          "exit"
          "duration"
          "time"
          {
            type = "directory";
            width = 24;
          }
          "command"
        ];
        syntax_highlight = true;
      };

      keys = {
        scroll_exits = false;
        exit_past_line_start = false;
        accept_past_line_end = true;
      };

      stats = {
        common_subcommands = [
          "cargo"
          "docker"
          "git"
          "jj"
          "kubectl"
          "nix"
          "npm"
          "pnpm"
          "systemctl"
        ];
        ignored_commands = [
          "cd"
          "clear"
          "ls"
          "pwd"
        ];
      };
    };
  };

  programs.nushell.extraConfig = lib.optionalString needsNushellIntegrationShim ''
    source ${atuinNushellConfig}
  '';
}
