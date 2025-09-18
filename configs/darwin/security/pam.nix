_:
{

  security.pam.services = {
    sudo_local = {
      enable = true;

      # Sudo through Touch ID and Apple Watch
      touchIdAuth = true;
      watchIdAuth = true; # Allow Login with Apple Watch (need to manually enable in System Settings)
      reattach = true; # This fixes Touch ID for sudo not working inside tmux and screen.
    };
  };
}
