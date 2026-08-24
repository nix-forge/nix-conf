{ config, lib, ... }:
let
  cfg = config.security.desktopKeyring;
in
{
  options.security.desktopKeyring.enable = lib.mkEnableOption ''
    a GNOME Keyring desktop profile providing Secret Service, PKCS#11, and the
    GCR SSH agent
  '';

  config = lib.mkIf cfg.enable {
    # GNOME Keyring remains the established desktop provider for Secret
    # Service and PKCS#11. Its NixOS module also installs the D-Bus service,
    # portal backend, capability-limited daemon wrapper, and PAM integration
    # needed to unlock the login keyring with the user's login password.
    services.gnome.gnome-keyring.enable = true;

    # Use a single SSH agent. GCR integrates with the desktop keyring; hosts
    # that use a hardware-token or another agent may explicitly disable it.
    services.gnome.gcr-ssh-agent.enable = lib.mkDefault true;

    assertions = [
      {
        assertion = !config.services.oo7.enable;
        message = "Choose either GNOME Keyring or oo7 for Secret Service; enabling both creates competing D-Bus providers and PAM unlock paths.";
      }
      {
        assertion = !(config.services.gnome.gcr-ssh-agent.enable && config.programs.ssh.startAgent);
        message = "GCR SSH agent and programs.ssh.startAgent cannot both be enabled; choose one SSH agent.";
      }
    ];

    # oo7 is GNOME's emerging Secret Service replacement, but migration from
    # GNOME Keyring rewrites stored keyrings and is currently one-way. Make a
    # future provider migration an explicit, tested host-local change.
  };
}
