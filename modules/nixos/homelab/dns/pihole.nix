{
  services.pihole-ftl = {
    enable = true;
    openFirewallDNS = false;
    openFirewallWebserver = false;
    settings = { };
    lists = [ ];
  };
}
