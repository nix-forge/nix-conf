{ ... }:
{

  security.pam.services = {
    sudo_local = {
      enable = true;

      # Sudo through Touch ID and Apple Watch
      touchIdAuth = true;
      watchIdAuth = true;
      reattach = true; # This fixes Touch ID for sudo not working inside tmux and screen.
    };
  };
}
