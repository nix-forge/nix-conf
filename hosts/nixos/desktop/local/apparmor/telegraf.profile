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

  # The SMART input invokes only the dedicated NixOS capability wrapper and
  # its pinned smartctl target.  Preserve the profile across that narrow
  # helper chain instead of accepting AppArmor-generated `null-` child
  # profiles, which would provide no useful path for later enforcement.
  /run/wrappers/wrappers.*/smartctl-telegraf ix,
  @smartmontoolsPackage@/bin/smartctl ix,
}
