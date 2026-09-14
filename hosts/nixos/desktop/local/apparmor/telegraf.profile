# Telegraf host-metrics AppArmor discovery-policy template.
#
# `security-apparmor.nix` replaces @telegrafPackage@ with the evaluated Nix
# package output.  The profile is attached only to the system Telegraf unit;
# it does not apply to other Go applications or to arbitrary Prometheus
# clients.  Telegraf intentionally reads kernel, mount, disk, SMART, and NVMe
# state, so its exact read set is learned under normal desktop use before an
# enforce policy is considered.

include <tunables/global>

profile nixos-telegraf @telegrafPackage@/bin/telegraf flags=(mediate_deleted) {
  include <abstractions/base>

  # Keep the profile through Telegraf's own executable.  The service does not
  # need a permissive transition to a general shell.  Any future helper
  # execution is therefore visible in the complain-mode audit trail.
  @telegrafPackage@/bin/telegraf mrix,

  # Go's runtime reads its own process statistics every second. Permit only
  # the service account's files so this known read does not flood discovery
  # logs or hide accesses that still need review.
  owner /proc/[0-9]*/stat r,

  # Reviewed host-metric reads recur every collection interval. Keep discovery
  # useful for new accesses without logging the same CPU and disk inventory.
  /proc/{devices,diskstats,loadavg,vmstat} r,
  /proc/1/mountinfo r,
  /run/utmp r,
  /sys/devices/system/cpu/cpu[0-9]*/ r,
  /sys/devices/system/cpu/cpu[0-9]*/topology/ r,
  /sys/devices/system/cpu/cpu[0-9]*/topology/core_cpus_list r,
  /sys/devices/virtual/block/dm-[0-9]*/dm/name r,
  /sys/devices/**/nvme/nvme[0-9]*/nvme[0-9]*n[0-9]*/wwid r,
  /sys/class/scsi_host/ r,
  /sys/devices/**/scsi_host/host[0-9]*/proc_name r,
  /sys/devices/**/usb[0-9]*/**/{idVendor,idProduct,bcdDevice} r,
  /dev/nvme[0-9]* r,
  /dev/sd[a-z] r,

  # Repeated SMART polls map the helper's C/C++ runtime and read the drive
  # database and block-device metadata. These observed read-only accesses
  # otherwise dominate the discovery log on every collection interval.
  /nix/store/????????????????????????????????-glibc-*/lib/lib{c,m}.so* mr,
  /nix/store/????????????????????????????????-gcc-*-lib/lib/libstdc++.so* mr,
  /nix/store/????????????????????????????????-gcc-*-libgcc/lib/libgcc_s.so* mr,
  @smartmontoolsPackage@/share/smartmontools/drivedb.h r,
  /run/udev/data/b[0-9]*:[0-9]* r,
  /dev/ r,

  # The SMART input invokes only the dedicated NixOS capability wrapper and
  # its pinned smartctl target.  Preserve the profile across that narrow
  # helper chain instead of accepting AppArmor-generated `null-` child
  # profiles, which would provide no useful path for later enforcement.
  /run/wrappers/wrappers.*/smartctl-telegraf ix,
  @smartmontoolsPackage@/bin/smartctl ix,
}
