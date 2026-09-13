{ pkgs, ... }: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;

  # Keep the existing Nix installer responsible for the daemon. Change this
  # only after reviewing that installer's nix-darwin integration instructions.
  nix.enable = false;
  environment.systemPackages = [
    pkgs.git
    pkgs.jq
  ];
  environment.variables.EDITOR = "vi";
  programs.zsh.enable = true;
  programs.zsh.interactiveShellInit = ''
    alias gs='git status --short --branch'
  '';

  # A system LaunchDaemon illustrates a managed job without account-specific
  # paths, credentials, network access, or an external service dependency.
  launchd.daemons.public-example-health = {
    serviceConfig = {
      Label = "org.nix-community.public-example-health";
      ProgramArguments = [ "${pkgs.coreutils}/bin/true" ];
      RunAtLoad = true;
    };
  };
}
