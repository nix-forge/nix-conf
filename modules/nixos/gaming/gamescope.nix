{
  programs.gamescope = {
    enable = true;

    # Do not apply global resolution, refresh-rate, HDR, VRR, or tearing flags:
    # those depend on the display and should be selected per game/session.
    # Keep the default unprivileged wrapper; GameMode handles the game's modest
    # scheduling boost, while granting Gamescope CAP_SYS_NICE is unnecessary.
    capSysNice = false;
  };
}
