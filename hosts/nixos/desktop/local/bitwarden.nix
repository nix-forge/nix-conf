{ pkgs, ... }: {
  # Bitwarden's Linux system-authentication flow asks the existing graphical
  # Polkit agent to authenticate the current user. Install only Bitwarden's
  # reviewed upstream action policy; do not add a permissive JavaScript rule.
  environment.etc."polkit-1/actions/com.bitwarden.Bitwarden.policy".source =
    "${pkgs.bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy";

  # This desktop has no fingerprint reader. Polkit authenticates with the
  # account password; Bitwarden does not require a fingerprint service.
  services.fprintd.enable = false;
}
