{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.workstation.workloads;
  mib =
    default: description:
    lib.mkOption {
      inherit default description;
      type = lib.types.ints.unsigned;
    };
  positive =
    default: description:
    lib.mkOption {
      inherit default description;
      type = lib.types.ints.positive;
    };
in
{
  # These are reviewed host choices, not guesses from a fluctuating MemAvailable
  # sample. Consumers derive admission, CLI ranges and units from this policy.
  options.workstation.workloads = {
    admission = {
      maximumSeconds = positive 1800 "Maximum direct executor lock and memory wait.";
      healthySeconds = positive 1 "Healthy admission interval before launching work.";
      pressureLimit = lib.mkOption {
        type = lib.types.ints.between 6 100;
        default = 50;
        description = "Stop admission at this full memory PSI avg10 percentage; reopen growth five points lower.";
      };
      growthHealthySeconds = positive 5 "Healthy demand interval before an upward grant.";
      growthStepMiB = positive 1024 "Maximum upward allocation step in MiB.";
    };
    aggregate = {
      memoryMiB = positive 10240 "Shared user workload RAM ceiling in MiB.";
      highMiB = positive 8192 "Shared user workload reclaim threshold in MiB.";
      swapMiB = mib 2048 "Shared user workload swap ceiling in MiB.";
    };
    bounded = {
      minimumMiB = positive 1024 "Smallest reviewed confined job allocation.";
      memoryMiB = positive 4096 "Default complete confined job allocation.";
      maximumMiB = positive 8192 "Largest reviewed confined job allocation.";
      reserveMiB = positive 2048 "Host headroom in addition to a confined allocation.";
      highPercent = lib.mkOption {
        type = lib.types.ints.between 1 99;
        default = 90;
        description = "Confined allocation reclaim threshold as a percentage of its hard limit.";
      };
      maximumSeconds = positive 1800 "Confined execution deadline ceiling.";
    };
    feedback = {
      memoryMiB = positive 2048 "Tiny diagnostic allocation in MiB.";
      highMiB = positive 1792 "Tiny diagnostic reclaim threshold in MiB.";
      swapMiB = mib 256 "Tiny diagnostic swap ceiling in MiB.";
      reserveMiB = positive 1024 "Host headroom in addition to a tiny diagnostic allocation.";
      maximumSeconds = positive 120 "Tiny diagnostic deadline ceiling.";
    };
    daemon = {
      memoryMiB = positive 10240 "Separately enforced shared Nix daemon RAM ceiling.";
      highMiB = positive 9216 "Measured shared daemon reclaim threshold in MiB.";
      swapMiB = mib 1024 "Shared Nix daemon swap ceiling in MiB.";
      reserveMiB = positive 4096 "Admission headroom beyond the shared daemon ceiling.";
      maximumSeconds = positive 86400 "Durable shared-daemon job deadline ceiling.";
    };
  };
  config = {
    assertions = [
      {
        assertion = lib.mod cfg.admission.growthStepMiB 1024 == 0;
        message = "Desktop memory growth steps must be whole GiB.";
      }
      {
        assertion = cfg.aggregate.highMiB < cfg.aggregate.memoryMiB;
        message = "The workstation aggregate reclaim threshold must leave room below its hard limit.";
      }
      {
        assertion =
          cfg.daemon.highMiB < cfg.daemon.memoryMiB && cfg.feedback.highMiB < cfg.feedback.memoryMiB;
        message = "Daemon and feedback reclaim thresholds must stay below their RAM ceilings.";
      }
      {
        assertion =
          cfg.bounded.minimumMiB <= cfg.bounded.memoryMiB
          && cfg.bounded.memoryMiB <= cfg.bounded.maximumMiB
          && cfg.bounded.maximumMiB <= cfg.aggregate.memoryMiB
          && cfg.feedback.memoryMiB <= cfg.aggregate.memoryMiB;
        message = "Workstation job defaults and ranges must fit the shared user allocation.";
      }
      {
        assertion = lib.all (value: lib.mod value 1024 == 0) [
          cfg.bounded.minimumMiB
          cfg.bounded.memoryMiB
          cfg.bounded.maximumMiB
          cfg.feedback.memoryMiB
          cfg.daemon.memoryMiB
        ];
        message = "Desktop executor allocation sizes must be whole GiB.";
      }
    ];
    system.build.workstationWorkloadPolicy = pkgs.writeText "workstation-workload-policy.json" (
      builtins.toJSON cfg
    );
  };
}
