_: {
  services.workstationJobs = {
    enable = true;
    reserveMiB = 3072;
    profiles.bounded = {
      backend = "darwin";
      memoryMiB = 2048;
      minimumMiB = 256;
      maximumMiB = 4096;
      # Large native release crates can exceed thirty minutes. Longer jobs
      # request their deadline explicitly and retain the same memory budget.
      maximumSeconds = 3600;
    };
  };
}
