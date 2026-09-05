{
  # Browser biometric unlock depends on the desktop broker remaining available
  # in this user's graphical session. Bitwarden itself still owns vault timeout,
  # lock-on-restart, and the explicit browser-approval handshake.
  programs.bitwardenDesktop.startAtLogin = true;
}
