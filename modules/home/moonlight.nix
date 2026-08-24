{ pkgs, ... }: {
  # Moonlight is the low-latency Sunshine client for the Apple-silicon MacBook.
  # Pairing state belongs to the user profile and is intentionally mutable: it
  # is cryptographic trust material, not a secret that belongs in the Nix store.
  home.packages = [ pkgs.moonlight-qt ];
}
