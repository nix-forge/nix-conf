{

  # port of https://gitlab.archlinux.org/archlinux/packaging/packages/realtime-privileges
  # see https://wiki.archlinux.org/title/Realtime_process_management
  # realtime processes have higher priority than normal processes and that's a good thing
  # user has to be in the audio group to be able to use realtime processes
  security.pam.loginLimits = [
    {
      domain = "@audio";
      type = "-";
      item = "rtprio";
      value = 99;
    }
    {
      domain = "@audio";
      type = "-";
      item = "memlock";
      value = "unlimited";
    }
    {
      domain = "@audio";
      type = "-";
      item = "nice";
      value = -11;
    }
    {
      domain = "@audio";
      item = "nofile";
      type = "soft";
      value = "99999";
    }
    {
      domain = "@audio";
      item = "nofile";
      type = "hard";
      value = "524288";
    }
  ];

  services.udev.extraRules = ''
    KERNEL=="cpu_dma_latency", GROUP="audio"
    KERNEL=="rtc0", GROUP="audio"
    KERNEL=="hpet", GROUP="audio"
  '';
}
