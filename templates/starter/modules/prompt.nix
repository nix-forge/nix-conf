{
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      # ASCII symbols work before a terminal font is configured.
      add_newline = false;
      format = "$directory$git_branch$character";
      command_timeout = 250;
      directory.style = "bold blue";
      git_branch.symbol = "git:";
      character = {
        success_symbol = "[>](bold green)";
        error_symbol = "[>](bold red)";
      };
    };
  };
}
