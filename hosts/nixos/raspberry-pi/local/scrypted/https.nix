{
  # Scrypted serves a self-signed HTTPS API on loopback. The shared proxy
  # permits this exception only for a literal loopback upstream.
  homelab.operations.lanHttps.sites.scrypted = {
    upstream = "https://127.0.0.1:10443";
    streaming = true;
  };
}
