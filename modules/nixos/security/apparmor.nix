{ config, lib, ... }:
let
  cfg = config.security.appArmorBaseline;
in
{
  options.security.appArmorBaseline.enable = lib.mkEnableOption ''
    the AppArmor mandatory-access-control baseline
  '';

  config = lib.mkIf cfg.enable {
    security.apparmor = {
      # AppArmor is a kernel LSM.  NixOS adds it to the kernel command line
      # and starts the policy loader; activation therefore requires a reboot
      # before any profile can protect a process.
      enable = true;

      # On NixOS, profiles frequently embed immutable store paths.  Caching
      # compiled policies therefore accumulates a new cache entry as closures
      # change, for little benefit on a desktop with a modest profile set.
      enableCache = lib.mkDefault false;

      # A newly loaded profile only affects future execs.  Do not terminate
      # existing GUI, container, or service processes on an ordinary switch;
      # profile rollouts must instead restart their own units deliberately.
      killUnconfinedConfinables = lib.mkDefault false;
    };

    assertions = [
      {
        assertion = lib.elem "apparmor" config.security.lsm;
        message = "The AppArmor baseline requires AppArmor in security.lsm; do not replace the LSM list without preserving it.";
      }
      {
        assertion = lib.elem "apparmor=1" config.boot.kernelParams;
        message = "The AppArmor baseline requires the apparmor=1 kernel parameter; do not force-replace boot.kernelParams without preserving security-module parameters.";
      }
      {
        assertion =
          !config.security.apparmor.killUnconfinedConfinables || config.security.apparmor.policies != { };
        message = "security.apparmor.killUnconfinedConfinables only makes sense with reviewed, explicit AppArmor policies; restart the affected service instead for a controlled rollout.";
      }
    ];

    # Policies, their enforce/complain state, and package-specific includes
    # are intentionally host-local.  Generic profiles cannot safely predict a
    # desktop's executable closure, home layout, devices, portals, or service
    # data.  Start each new policy in `complain`, exercise it, review journal
    # events with aa-logprof, commit the resulting declarative policy, then
    # switch only that policy to `enforce`.
  };
}
