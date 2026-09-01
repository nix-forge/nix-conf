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
          text = ''
            if systemd-bless-boot good; then
              exit 0
            else
              status="$?"
            fi

            efi_var=/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
            if [[ -r "$efi_var" ]]; then
              entry_path="$(strings -el "$efi_var")"
              entry_path="''${entry_path//\\//}"
              if [[ "$entry_path" =~ ^/loader/entries/nixos-[[:xdigit:]]{64}\+[0-9]+-[0-9]+\.conf$ ]] \
                && [[ ! -e "/boot$entry_path" ]]; then
                echo "Ignoring stale LoaderBootCountPath for pruned entry: $entry_path" >&2
                exit 0
              fi
            fi

            exit "$status"
          '';
        }
      ))
    ];
  };
}
