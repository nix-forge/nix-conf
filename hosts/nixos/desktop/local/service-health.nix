{
  config,
  lib,
  pkgs,
  ...
}:
let
  active = unit: {
    command = [
      "${pkgs.systemd}/bin/systemctl"
      "is-active"
      "--quiet"
      unit
    ];
    timeoutSeconds = 15;
  };
in
{
  # Individual probes avoid systemctl's any-active semantics for multiple units.
  # User-session functionality still needs the runtime acceptance checks.
  hardware.storage.encryptedRoot.health.probes = {
    nix-daemon-socket = active "nix-daemon.socket";
  }
  // lib.optionalAttrs config.networking.networkmanager.enable {
    network-manager = active "NetworkManager.service";
  }
  // lib.optionalAttrs config.services.resolved.enable {
    dns-stub = active "systemd-resolved.service";
  }
  // lib.optionalAttrs config.services.unbound.enable {
    dns-resolver = active "unbound.service";
  }
  // lib.optionalAttrs config.services.greetd.enable {
    login-manager = active "greetd.service";
  }
  // lib.optionalAttrs config.services.openssh.enable {
    remote-access = active "sshd.service";
  };
}
