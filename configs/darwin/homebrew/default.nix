{ inputs, config, ... }:
{
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
    ./environment.nix
  ];

  nix-homebrew = {
    # Install Homebrew under the default prefix
    enable = true;

    # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
    enableRosetta = false;

    # User owning the Homebrew prefix
    user = config.system.primaryUser;

    # Optional: Declarative tap management
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };

    # Optional: Enable fully-declarative tap management
    # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
    mutableTaps = false;

    # Automatically migrate existing Homebrew installations
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    global.autoUpdate = false;
    onActivation = {
      autoUpdate = false;
      upgrade = true;
      cleanup = "zap";
    };

    # caskArgs.require_sha = true; # Uncomment if you want strict checksum checks (can be noisy)

    taps = builtins.attrNames config.nix-homebrew.taps;

    # TODO: move this to config specific to the user or system
    casks = [
      "signal"
      "discord"
      "chatgpt"
      "chatgpt-atlas"
      "steam"
    ];

    # If you truly need a formula that Nix doesn’t provide well, add here sparingly:
    # brews = [
    #   # "mas" # Needed below for Mac App Store management
    #   # "gnupg"
    # ];

    # Optional: Mac App Store apps (requires 'mas' formula and that you are signed into App Store)
    # masApps = {
    #   "Xcode" = 497799835;
    #   "Magnet" = 441258766;
    #   "Slack" = 803453959;
    # };
  };
}
