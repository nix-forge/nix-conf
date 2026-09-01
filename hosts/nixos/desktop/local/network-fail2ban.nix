{
  networking.fail2ban.enable = true;

  # Do not exempt the whole private network. This desktop permits SSH only
  # from private IPv4 and IPv6 ranges, so doing so would remove Fail2ban's
  # protection from every Wi-Fi/LAN peer. Add only a deliberately static,
  # out-of-band recovery address to `services.fail2ban.ignoreIP` if one is
  # ever required; normal SSH key authentication does not consume retries.
  services.fail2ban.ignoreIP = [ ];
}
