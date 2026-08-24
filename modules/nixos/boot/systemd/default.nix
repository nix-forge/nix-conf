{ config, lib, ... }: {
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
  };
}
