{ pkgs, ... }: {
  # Make Ghostty's terminal description available to SSH clients.  This is
  # intentionally the small terminfo output rather than the graphical terminal
  # package: the desktop only needs to understand TERM=xterm-ghostty.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];
}
