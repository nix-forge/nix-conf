{ modules, ... }:
{
  system = "x86_64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  stateVersion = "24.11";
  uid = 1000;

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
