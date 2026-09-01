{ config, lib, ... }:
let
  cfg = config.networking.tarpit;
  isIPv4 = cfg.addressFamily == "ipv4";
  listenAddress = if isIPv4 then "0.0.0.0" else "[::]";
  connectionType = if isIPv4 then "tcp4" else "tcp6";
  sourceExpression = lib.concatStringsSep ", " cfg.allowedSources;
  isPublicSourceSet = builtins.elem (if isIPv4 then "0.0.0.0/0" else "::/0") cfg.allowedSources;
  firewallRule =
    if isIPv4 then
      "ip saddr { ${sourceExpression} } tcp dport ${toString cfg.port} accept"
    else
      "ip6 saddr { ${sourceExpression} } tcp dport ${toString cfg.port} accept";
in
{
  options.networking.tarpit = {
    enable = lib.mkEnableOption ''
      a bounded SSH tarpit on an explicitly selected network scope
    '';

    addressFamily = lib.mkOption {
      type = lib.types.enum [
        "ipv4"
        "ipv6"
      ];
      default = "ipv4";
      description = "Address family served by this tarpit instance.";
    };

    allowedSources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "198.51.100.0/24" ];
      description = ''
        Source addresses or CIDRs permitted to reach the tarpit. This must be
        chosen in host-local configuration; the module never opens a port to
        every network by default.
      '';
    };

    allowPublicAccess = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit acknowledgement that a 0.0.0.0/0 or ::/0 tarpit listener is
        acceptable for this host. Public tarpits can attract sustained traffic
        and are better suited to a dedicated, monitored decoy host.
      '';
    };

    port = lib.mkOption {
      type = lib.types.ints.between 1024 65535;
      default = 2222;
      description = "Unprivileged TCP port for the SSH-decoy listener.";
    };

    maxClients = lib.mkOption {
      type = lib.types.ints.between 1 4096;
      default = 128;
      description = ''
        Maximum simultaneous tarpit connections. A finite limit preserves
        file descriptors and memory for the desktop's real workloads.
      '';
    };

    intervalMs = lib.mkOption {
      type = lib.types.ints.between 1000 60000;
      default = 5000;
      description = ''
        Delay between decoy SSH-banner fragments. A slower banner minimizes
        outbound work while retaining the tarpit behaviour.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.allowedSources != [ ];
        message = "networking.tarpit requires an explicit, host-local allowedSources list.";
      }
      {
        assertion = cfg.allowPublicAccess || !isPublicSourceSet;
        message = "networking.tarpit requires allowPublicAccess = true before opening a tarpit to the entire Internet.";
      }
      {
        assertion = !lib.elem cfg.port config.services.openssh.ports;
        message = "networking.tarpit.port must not overlap an OpenSSH listener.";
      }
      {
        assertion = config.networking.firewall.enable || config.networking.nftables.enable;
        message = "networking.tarpit requires an enabled NixOS firewall or nftables ruleset.";
      }
    ];

    # `endlessh-go` is the maintained NixOS SSH-decoy implementation. Unlike
    # the unsupported xt_TARPIT kernel extension, it has a finite client cap
    # and a strongly sandboxed, dynamically allocated systemd service.
    services.endlessh-go = {
      enable = true;
      inherit listenAddress;
      inherit (cfg) port;
      openFirewall = false;
      prometheus.enable = false;
      extraOptions = [
        "-conn_type=${connectionType}"
        "-max_clients=${toString cfg.maxClients}"
        "-interval_ms=${toString cfg.intervalMs}"
        "-line_length=32"
      ];
    };

    # Keep the listener behind an explicit source policy. `openFirewall` is
    # deliberately off above: its global port rule would defeat this boundary.
    networking.firewall.extraInputRules = lib.mkAfter ''
      ${firewallRule} comment "allow SSH tarpit from explicitly selected sources"
    '';
  };
}
