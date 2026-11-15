{
  config,
  lib,
  osConfig,
  ...
}:
let
  policy = osConfig.workstation.workloads;
in
{
  services.workstationJobs = {
    enable = true;
    workstationTask = lib.getExe' config.lib.workstationTask "workstation-task";
    reserveMiB = policy.bounded.reserveMiB;
    admissionHealthySeconds = policy.admission.healthySeconds;
    admissionPressureLimit = policy.admission.pressureLimit;
    growthHealthySeconds = policy.admission.growthHealthySeconds;
    growthStepMiB = policy.admission.growthStepMiB;
    profiles = {
      bounded = {
        backend = "desktop";
        executionMode = "bounded";
        inherit (policy.bounded)
          memoryMiB
          minimumMiB
          maximumMiB
          maximumSeconds
          ;
      };
      host-check = {
        backend = "desktop";
        executionMode = "host-bounded";
        inherit (policy.bounded)
          memoryMiB
          minimumMiB
          maximumMiB
          maximumSeconds
          ;
      };
      feedback = {
        backend = "desktop";
        executionMode = "feedback";
        inherit (policy.feedback) memoryMiB maximumSeconds;
        minimumMiB = policy.feedback.memoryMiB;
        maximumMiB = policy.feedback.memoryMiB;
      };
      daemon = {
        backend = "desktop";
        executionMode = "daemon";
        inherit (policy.daemon) memoryMiB maximumSeconds;
        minimumMiB = policy.daemon.memoryMiB;
        maximumMiB = policy.daemon.memoryMiB;
      };
    };
  };
  assertions = [
    {
      assertion = lib.all (
        profile:
        if profile.backend != "desktop" then
          true
        else if
          lib.elem profile.executionMode [
            "bounded"
            "host-bounded"
          ]
        then
          profile.minimumMiB >= policy.bounded.minimumMiB
          && profile.maximumMiB <= policy.bounded.maximumMiB
          && profile.maximumSeconds <= policy.bounded.maximumSeconds
        else if profile.executionMode == "feedback" then
          profile.minimumMiB == policy.feedback.memoryMiB
          && profile.maximumMiB == policy.feedback.memoryMiB
          && profile.maximumSeconds <= policy.feedback.maximumSeconds
        else
          profile.minimumMiB == policy.daemon.memoryMiB
          && profile.maximumMiB == policy.daemon.memoryMiB
          && profile.maximumSeconds <= policy.daemon.maximumSeconds
      ) (lib.attrValues config.services.workstationJobs.profiles);
      message = "Desktop queue profiles must fit the actual runner's execution modes and limits.";
    }
  ];
}
