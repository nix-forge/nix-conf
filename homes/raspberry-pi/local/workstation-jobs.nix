_: {
  # This small service host is not a desktop builder. Leave capacity for its
  # declared home services; strict aggregate cgroup limits bound finite workers.
  services.workstationJobs = {
    enable = true;
    reserveMiB = 512;
    aggregateMiB = 384;
    profiles.bounded = {
      backend = "systemd";
      memoryMiB = 256;
      minimumMiB = 64;
      maximumMiB = 384;
      maximumSeconds = 1200;
    };
  };
}
