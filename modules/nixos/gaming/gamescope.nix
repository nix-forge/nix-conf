{
  programs.gamescope = {
    enable = true;
    # HDR-capable Vulkan clients nested under Gamescope need its implicit WSI
    # layer. NixOS installs both 64-bit and 32-bit variants with this switch.
    enableWsi = true;

    # Do not apply global resolution, refresh-rate, HDR, VRR, or tearing flags:
    # those depend on the display and should be selected per game/session.
    # Keep the default unprivileged wrapper; GameMode handles the game's modest
    # scheduling boost, while granting Gamescope CAP_SYS_NICE is unnecessary.
    capSysNice = false;
  };
}
