{ config, lib, ... }:
let
  cfg = config.networking.resolvedBaseline;
in
{
  options.networking.resolvedBaseline.enable = lib.mkEnableOption "the systemd-resolved local-stub baseline";

  config = lib.mkIf cfg.enable {
    services.resolved = {
      enable = true;
      settings.Resolve = {
        # Keep the NixOS-managed /etc/resolv.conf pointed at the full local
        # stub on 127.0.0.53. Do not add DNSStubListenerExtra: DNS resolution
        # is a local-client service, never a LAN DNS service on this baseline.
        DNSStubListener = true;

        # LLMNR is vulnerable to local-link spoofing. mDNS is deliberately off
        # as well: a host that needs it should opt in locally and configure the
        # matching network links. `resolve` alone still creates UDP/5353
        # listeners, so it is not a cost-free default.
        LLMNR = false;
        MulticastDNS = false;

        # Preserve ordinary /etc/hosts behaviour and avoid sending bare local
        # labels to a recursive resolver. Search/routing domains and any local
        # discovery protocol remain explicit host-local decisions.
        ReadEtcHosts = true;
        ResolveUnicastSingleLabel = false;

        # This system's upstream resolver policy can be a loopback blocker.
        # Its bounded cache is the sole cache owner, preventing redundant
        # caching and stale/filtered answer inconsistencies in resolved.
        CacheFromLocalhost = false;
      };
    };

    assertions = [
      {
        assertion = !config.networking.useHostResolvConf;
        message = "networking.resolvedBaseline requires the NixOS-managed systemd-resolved resolv.conf stub.";
      }
      {
        assertion = config.services.resolved.settings.Resolve.DNSStubListener == true;
        message = "networking.resolvedBaseline requires the local DNS stub listener; do not point /etc/resolv.conf at an external listener.";
      }
    ];
  };
}
