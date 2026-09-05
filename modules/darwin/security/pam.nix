_: {

  # Keep Apple's protection that disables biometric authorization while the
  # screen is being recorded or remotely observed.
  system.defaults.CustomUserPreferences."com.apple.security.authorization".ignoreArd = false;

  security.pam.services = {
    sudo_local = {
      enable = true;

      # Use Apple's native Touch ID module. Password remains the fallback.
      touchIdAuth = true;
      watchIdAuth = false;
      reattach = false;
    };
  };
}
