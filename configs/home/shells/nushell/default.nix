{ ... }:
{
  programs.nushell = {
    enable = true;

    settings = {
      # Remove the welcome banner message
      show_banner = false;
    };
  };
}
