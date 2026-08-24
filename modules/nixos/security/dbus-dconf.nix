{ config, lib, ... }:
let
  cfg = config.security.dbusDconfBaseline;
in
{
  options.security.dbusDconfBaseline.enable = lib.mkEnableOption ''
    the D-Bus Broker and dconf desktop-integration baseline
  '';

  config = lib.mkIf cfg.enable {
    services.dbus = {
      enable = true;

      # dbus-broker is the Linux-native, specification-compatible broker. It
      # provides resource accounting and audit logging while preserving the
      # standard system and session bus interfaces expected by desktop software.
      implementation = "broker";

      # Enable D-Bus/AppArmor mediation when the kernel and profiles support
      # it, but do not make the message bus unavailable during an ordinary
      # AppArmor rollout or recovery boot. `required` belongs only in a fully
      # profiled, tested appliance configuration.
      apparmor = "enabled";
    };

    # dconf supplies the GSettings backend and its session-activated service.
    # The NixOS module installs the required D-Bus activation metadata and
    # GIO module; no hand-written activation service is needed.
    programs.dconf.enable = true;

    assertions = [
      {
        assertion = config.services.dbus.enable;
        message = "security.dbusDconfBaseline requires the system D-Bus service.";
      }
      {
        assertion = config.services.dbus.implementation == "broker";
        message = "security.dbusDconfBaseline requires dbus-broker; use a dedicated compatibility profile if a legacy service requires dbus-daemon.";
      }
      {
        assertion = config.services.dbus.apparmor == "enabled";
        message = "security.dbusDconfBaseline requires D-Bus AppArmor mediation to be enabled when available.";
      }
      {
        assertion = config.programs.dconf.enable;
        message = "security.dbusDconfBaseline requires dconf for GSettings-compatible desktop applications.";
      }
    ];

    # Do not add broad custom D-Bus XML allow rules here. The system bus is a
    # security boundary: each enabled service must ship its own narrow policy
    # and use Polkit or service-level authorization for privileged operations.
    # The user session bus is owned by its logged-in user, so D-Bus policy does
    # not substitute for sandboxing or portals. Existing portal, Polkit,
    # keyring, and UDisks modules remain the appropriate owners of their D-Bus
    # activation metadata and authorization policy.
  };
}
