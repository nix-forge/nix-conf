{ lib, ... }:
{
  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;

      format = lib.concatStrings [
        "$directory"
        "$character"
      ];

      right_format = "$all";
      command_timeout = 1000;

      character = {
        vicmd_symbol = "[N] >>>";
        success_symbol = "[➜](bold green)";
      };

      git_branch = {
        format = "[$symbol$branch(:$remote_branch)]($style)";
      };

    };
  };
}
