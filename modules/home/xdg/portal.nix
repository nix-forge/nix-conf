{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  cfg = config.xdg.portalHomeIntegration;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  systemPortalEnabled = osConfig != null && (osConfig.xdg.portal.enable or false);
in
{
  options.xdg.portalHomeIntegration.enable = lib.mkEnableOption ''
    coordination between this Home Manager profile and XDG Desktop Portals
  '';

  config = lib.mkIf cfg.enable {
    # A portal is a user-session D-Bus service, but on NixOS its implementation
    # and activation metadata must be installed by the operating system.  Do
    # not create a second Home Manager portal stack on an integrated NixOS
    # desktop: duplicate portal definitions lead to backend-selection races.
    assertions = [
      {
        assertion = !isLinux || systemPortalEnabled || config.xdg.portal.enable;
        message = ''
          xdg.portalHomeIntegration requires either an OS-managed portal or a
          desktop-specific Home Manager module that enables xdg.portal.
        '';
      }
    ];

    # A standalone Linux profile needs a toolkit fallback in addition to its
    # desktop-specific backend.  This is deliberately a default: a DE module
    # can supply a stronger, native backend list without duplicate packages.
    # Do not write a global portals.conf here—its high precedence would
    # override GNOME, KDE, COSMIC, and other session-specific selections.
    xdg.portal = lib.mkIf (isLinux && !systemPortalEnabled) {
      extraPortals = lib.mkDefault [ pkgs.xdg-desktop-portal-gtk ];
      xdgOpenUsePortal = lib.mkDefault true;
    };
  };
}
