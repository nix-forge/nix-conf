{
  programs.gamemode = {
    enable = true;
    enableRenice = true;

    settings = {
      general = {
        # XanMod uses the upstream scheduler, which does not provide SCHED_ISO.
        # Explicitly keep this off instead of requesting an unavailable policy.
        softrealtime = "off";

        # Give games a modest, temporary CPU and I/O scheduling preference
        # without risking priority inversion in GPU driver or compositor work.
        renice = 10;
        ioprio = 0;
        inhibit_screensaver = 1;
      };
    };
  };
}
