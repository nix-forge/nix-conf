{ config, lib, ... }:
let
  cfg = config.networking.fail2ban;
in
{
  options.networking.fail2ban.enable = lib.mkEnableOption ''
    the SSH Fail2ban baseline
  '';

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.openssh.enable;
        message = "networking.fail2ban protects the OpenSSH service and requires services.openssh.enable.";
      }
      {
        assertion = config.networking.firewall.enable || config.networking.nftables.enable;
        message = "networking.fail2ban requires an enabled NixOS firewall or nftables ruleset so bans can be enforced.";
      }
    ];

    services.fail2ban = {
      enable = true;

      # A small number of authentication failures from a legitimate key-only
      # client should not normally occur. Five attempts in fifteen minutes is
      # therefore a useful threshold for username/key probing without being
      # fragile during ordinary administration.
      bantime = lib.mkDefault "1h";
      maxretry = lib.mkDefault 5;

      # Keep repeat offenders out for increasingly longer periods, but cap
      # history and the maximum ban length so the local SQLite database stays
      # small and an accidental ban is recoverable.
      bantime-increment = {
        enable = lib.mkDefault true;
        rndtime = lib.mkDefault "5m";
        maxtime = lib.mkDefault "7d";
        overalljails = lib.mkDefault true;
      };

      daemonSettings.Definition = {
        # Ban history is needed for incremental bans. Thirty days covers
        # recurring probes while avoiding indefinitely retained IP history.
        dbpurgeage = lib.mkDefault "30d";
      };

      jails = {
        DEFAULT.settings = {
          # The NixOS module already selects the systemd journal backend. Do
          # not add log files or a polling service merely to protect sshd.
          findtime = lib.mkDefault "15m";

          # Authentication logs already contain numeric remote addresses.
          # Skipping reverse DNS prevents latency, avoids DNS-dependent
          # matching, and ensures a ban is always tied to the source address.
          usedns = lib.mkDefault "no";
        };

        # Restrict the shared baseline to the one exposed authentication
        # service. Other jails must be explicitly selected with application-
        # specific, host-local log and false-positive analysis.
        sshd.enabled = lib.mkDefault true;
      };
    };

    # Fail2ban's sshd filter needs SSH failure records. NixOS's upstream
    # module also defaults this to VERBOSE; repeat it here as an explicit part
    # of this baseline while leaving a host free to raise the level further.
    services.openssh.settings.LogLevel = lib.mkDefault "VERBOSE";
  };
}
