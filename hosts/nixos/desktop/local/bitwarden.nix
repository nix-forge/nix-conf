{ pkgs, ... }: {
  # Bitwarden's Linux system-authentication flow asks the existing graphical
  # Polkit agent to authenticate the current user. Install only Bitwarden's
  # reviewed upstream action policy; do not add a permissive JavaScript rule.
  environment.etc."polkit-1/actions/com.bitwarden.Bitwarden.policy".source =
    "${pkgs.bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy";

  # Use NixOS's maintained fprintd integration for login, sudo, Polkit, greetd,
  # and screen lockers. NixOS adds pam_fprintd as a `sufficient` authentication
  # rule, so a successful fingerprint authenticates while failure or unavailable
  # hardware falls through to the existing password rules. Do not add autologin,
  # empty-password, or Polkit authorization-bypass rules alongside this.
  services.fprintd.enable = true;
}
