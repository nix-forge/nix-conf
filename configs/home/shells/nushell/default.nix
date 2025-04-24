{ config, lib, ... }:
{
  programs.nushell = {
    enable = true;

    # Move home-manager settings to the nushell config
    # https://github.com/nix-community/home-manager/issues/4313
    shellAliases = config.home.shellAliases;
    environmentVariables = config.home.sessionVariables;

    settings = {
      # Remove the welcome banner message
      show_banner = false;
    };

    extraEnv = lib.mkAfter ''
      let nixPaths = [
        ($env.HOME | path join ".nix-profile/bin")
        "/etc/profiles/per-user/${config.home.username}/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ]

      let currentPath = $env.PATH | split row (char esep)
      let combinedPath = ($nixPaths ++ $currentPath) | uniq
      $env.PATH = $combinedPath
    '';
  };
}
