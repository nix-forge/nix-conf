{ modules, ... }:
{
  system = "aarch64-darwin";
  username = "ianmh";
  homeDirectory = "/Users/ianmh";
  uid = 501;

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  modules = with modules; [
    ## Base
    base-version
    # base-fonts  # Requires custom flake packages
    base-xdg
    determinate

    ## Shells
    shells-aliases
    shells-starship
    shells-zoxide
    shells-carapace
    shells-eza

    ## Development
    dev-direnv

    ## Programs
    programs-ssh

    ## Per-host configuration
    # ./ssh.nix     # Requires agenix
    # ./secrets.nix  # Requires nix-secrets input
  ];
}
