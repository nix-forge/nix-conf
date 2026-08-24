{ config, lib, ... }:
let
  cfg = config.security.usbguardBaseline;
in
{
  options.security.usbguardBaseline.enable = lib.mkEnableOption ''
    a USBGuard deny-by-default USB-device authorization baseline
  '';

  config = lib.mkIf cfg.enable {
    services.usbguard = {
      enable = true;

      # A policy is an authorization boundary, not merely an audit record.
      # The host must provide an explicit, reviewed rule set for its permanent
      # devices; anything else remains blocked.
      implicitPolicyTarget = "block";
      presentDevicePolicy = "apply-policy";
      presentControllerPolicy = "keep";
      insertedDevicePolicy = "apply-policy";

      # Retain authorization state if the daemon unexpectedly stops instead
      # of silently restoring all devices. A previous boot generation and the
      # host-local recovery specialisation remain deliberate escape routes.
      restoreControllerDeviceState = false;

      # Keep policy administration local and declarative. A graphical D-Bus
      # prompt cannot reliably convey a newly attached device's properties, and
      # mutable approvals would diverge from the immutable Nix policy. Root
      # can inspect the policy through the local IPC socket with sudo usbguard.
      IPCAllowedUsers = lib.mkForce [ "root" ];
      IPCAllowedGroups = lib.mkForce [ ];
      dbus.enable = lib.mkForce false;

      # Include topology when a rule is generated or added deliberately. This
      # prevents an otherwise identical device from being trusted when moved
      # to another physical USB port.
      deviceRulesWithPort = true;
    };

    environment.systemPackages = [ config.services.usbguard.package ];

    assertions = [
      {
        assertion = config.services.usbguard.rules != null;
        message = "security.usbguardBaseline requires an explicit host-local services.usbguard.rules policy; never enable it with a blanket allow rule.";
      }
      {
        assertion = config.services.usbguard.implicitPolicyTarget == "block";
        message = "security.usbguardBaseline requires services.usbguard.implicitPolicyTarget = \\\"block\\\".";
      }
      {
        assertion = config.services.usbguard.presentDevicePolicy == "apply-policy";
        message = "security.usbguardBaseline requires USB devices already connected at daemon start to be checked against policy.";
      }
      {
        assertion = config.services.usbguard.insertedDevicePolicy == "apply-policy";
        message = "security.usbguardBaseline requires newly attached USB devices to be checked against policy.";
      }
      {
        assertion = !config.services.usbguard.dbus.enable;
        message = "security.usbguardBaseline keeps USBGuard D-Bus administration disabled; use reviewed host-local rules instead.";
      }
      {
        assertion =
          config.services.usbguard.IPCAllowedUsers == [ "root" ]
          && config.services.usbguard.IPCAllowedGroups == [ ];
        message = "security.usbguardBaseline permits USBGuard policy IPC only to root.";
      }
      {
        assertion = !config.services.usbguard.restoreControllerDeviceState;
        message = "security.usbguardBaseline must not silently restore all USB authorizations when USBGuard stops.";
      }
    ];

    # USBGuard's NixOS service already receives a restrictive systemd sandbox
    # (private devices, strict device policy, no network, a minimal capability
    # set, and a 0077 umask). Keep that upstream hardening intact instead of
    # widening it here. Device identities and topology are necessarily
    # host-specific, so the rule set belongs in hosts/<host>/local/.
  };
}
