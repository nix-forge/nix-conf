{
  # Enable in-memory compressed devices and swap space provided by the zram kernel module.
  # By enabling this, we can store more data in memory before falling back to
  # disk-based swap devices, improving I/O performance under memory pressure.
  # and thus improve I/O performance when we have a lot of memory.
  #
  #   https://www.kernel.org/doc/Documentation/blockdev/zram.txt
  zramSwap = {
    enable = true;
    # one of "lzo", "lz4", "zstd"
    algorithm = "zstd";
    # Priority of the zram swap devices.
    # It should be a number higher than the priority of your disk-based swap devices
    # (so that the system will fill the zram swap devices before falling back to disk swap).
    priority = 5;
    # Maximum total amount of memory that can be stored in the zram swap devices (as a percentage of your total memory).
    # Defaults to 1/2 of your total RAM. Run zramctl to check how good memory is compressed.
    # This doesn’t define how much memory will be used by the zram swap devices.
    memoryPercent = 50;
  };

  # Do not enable zswap here. zswap and zram both compress swapped pages in
  # memory; stacking them causes redundant compression and is unsupported by
  # NixOS. Hosts using this module therefore use zram as the sole compressed
  # swap layer.
}
