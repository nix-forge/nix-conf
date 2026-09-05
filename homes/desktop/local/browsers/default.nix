{
  imports = [
    ../../../shared/local/browsers/common.nix
    ../../../shared/local/browsers/bitwarden.nix
    ../../../shared/local/browsers/extensions.nix
    ../../../shared/local/browsers/search.nix
    ../../../shared/local/browsers/zen.nix
  ];

  # Blocky and Unbound own encrypted DNS on this host. Avoid sending a second,
  # conflicting DNS policy through each browser.
  programs.browserSuite.systemResolverPolicy.DNSOverHTTPS = {
    Enabled = false;
    Locked = true;
  };
}
