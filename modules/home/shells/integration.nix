{ config, ... }: {
  # Keep integrations tied to the shells that are actually enabled. This lets
  # every program use Home Manager's normal per-shell defaults without
  # accidentally initializing integrations for an unused shell.
  home.shell = {
    enableShellIntegration = false;
    enableBashIntegration = config.programs.bash.enable;
    enableFishIntegration = config.programs.fish.enable;
    enableIonIntegration = config.programs.ion.enable;
    enableNushellIntegration = config.programs.nushell.enable;
    enableZshIntegration = config.programs.zsh.enable;
  };
}
