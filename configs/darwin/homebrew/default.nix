{
  homebrew = {
    enable = true;
    global.autoUpdate = false;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    # TODO: move this to config specific to the user or system
    casks = [
      "discord"
      "signal"
    ];
  };
}
