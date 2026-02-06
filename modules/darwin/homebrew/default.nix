{ inputs, config, ... }:
{
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
    ./environment.nix
  ];

  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    autoMigrate = true;

    user = config.system.primaryUser;

    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
  };

  homebrew = {
    enable = true;
    global.autoUpdate = false;
    onActivation = {
      autoUpdate = false;
      upgrade = true;
      cleanup = "zap";
    };

    caskArgs.require_sha = true;

    taps = builtins.attrNames config.nix-homebrew.taps;
  };
}
