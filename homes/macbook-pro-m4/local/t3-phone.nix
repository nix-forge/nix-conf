_: {
  # A stable home HTTPS endpoint without a listener on untrusted Wi-Fi.
  # The desktop alias uses its reserved LAN address, reachable both at home
  # and through the home WireGuard VPN. The shared service owns reconnection.
  services.sshForwards.t3code-phone-tunnel = {
    host = "desktop";
    direction = "remote";
    bindPort = 3774;
    targetPort = 3773;
    connectTimeoutSeconds = 10;
    serverAliveInterval = 15;
  };
}
