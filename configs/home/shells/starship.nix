{ lib, config, ... }:
{
  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;
      command_timeout = 800;
      scan_timeout = 50;

      format = lib.concatStrings [
        "$directory"
        "$character"
      ];

      right_format = "$all";

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vicmd_symbol = "[❮](bold yellow)";
      };

      directory = {
        style = "bold blue";
        truncation_length = 3;
        truncate_to_repo = true;
        read_only = " ";
        read_only_style = "bold red";
      };

      cmd_duration = {
        min_time = 2000;
        format = "[ 󱫍 $duration]($style) ";
        style = "yellow";
      };

      git_branch = {
        symbol = " ";
        format = "[$symbol$branch(:$remote_branch)]($style) ";
      };

      git_status = {
        stashed = " ";
        conflicted = " ";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕";
        up_to_date = "";
        untracked = "?\${count}";
        modified = "•\${count}";
        staged = "+\${count}";
        renamed = "»\${count}";
        deleted = "✘\${count}";
      };

      git_state = {
        format = "([ $state( $progress_current/$progress_total)]($style)) ";
        style = "bold red";
      };

      status = {
        disabled = false;
        format = "[$symbol$common_meaning$signal_name$maybe_int]($style) ";
        map_symbol = true;
        pipestatus = true;
        recognize_signal_code = true;
        style = "bold red";
        success_symbol = "";
        symbol = " ";
        not_executable_symbol = " ";
        not_found_symbol = " ";
        sigint_symbol = " ";
        signal_symbol = "⚡ ";

      };

      package = {
        symbol = "󰏗 ";
      };

      nix_shell = {
        disabled = true; # Not super useful as it will just display "impure (nix-shell-env)"
        symbol = " ";
        heuristic = true;
      };

      python = {
        symbol = "󰌠 ";
      };

      conda = {
        symbol = " ";
      };

      bun = {
        symbol = " ";
      };

      nodejs = {
        symbol = " ";
      };

      container = {
        symbol = " ";
      };

      docker_context = {
        symbol = " ";
      };

      c = {
        symbol = " ";
      };

      cpp = {
        symbol = " ";
      };

      cmake = {
        symbol = " ";
      };

      os.symbols = {
        NixOS = " ";
        Macos = " ";
        Linux = " ";
      };

      shell = {
        disabled = false;
      }
      // lib.optionalAttrs (lib.hasAttr "SHELL" config.home.sessionVariables) (
        let
          shellPath = config.home.sessionVariables.SHELL;
          shellName = lib.last (lib.splitString "/" shellPath);
        in
        {
          # Disable the default shell indicator (see shell name when in not default shell)
          "${shellName}_indicator" = "";
        }
      );
    };
  };
}
