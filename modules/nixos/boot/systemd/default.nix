{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.boot.loader.systemd-boot.enable {
    boot.loader.systemd-boot = {
      # Keep enough rollback generations for normal recovery without filling
      # an ESP whose capacity is intentionally a host-local storage decision.
      configurationLimit = lib.mkDefault 12;

      # Kernel-command-line editing can bypass normal boot-time protections.
      # A host can still select an older generation or change its declarative
      # configuration; local recovery policy may deliberately override this.
      editor = lib.mkDefault false;

      # Mark a generation bad when it repeatedly fails before userspace is
      # healthy, then fall back to an older working generation.
      bootCounting.enable = lib.mkDefault true;
    };

    # systemd-boot passes the counted-entry path to userspace in a volatile EFI
    # variable.  An online switch can prune that entry before systemd restarts
    # the blessing unit, leaving the variable pointing at a file that no
    # longer exists.  Treat only that narrowly identified stale NixOS entry as
    # already handled.  Other blessing failures still fail the unit, so boot
    # counting continues to provide rollback protection for actual boot issues.
    systemd.services."systemd-bless-boot".serviceConfig.ExecStart = lib.mkForce [
      ""
      (lib.getExe (
        pkgs.writeShellApplication {
          name = "nix-conf-systemd-bless-boot";
          runtimeInputs = [
            pkgs.binutils
            pkgs.systemd
          ];
          text = (import ../../../../lib/templates/text.nix) ./scripts/nix-conf-systemd-bless-boot.sh {
            pkgs_systemd = pkgs.systemd;
            esp_path = lib.escapeShellArg config.boot.loader.efi.efiSysMountPoint;
          };
        }
      ))
    ];
  };
}
