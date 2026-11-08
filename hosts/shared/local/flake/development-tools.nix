{ self, ... }: {
  perSystem = { lib, system, ... }: {
    # Use the host-owned runner and its exact resource policy, without
    # building or activating unrelated desktop applications and services.
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      workstation-task = self.nixosConfigurations.desktop.config.system.build.workstationTask;
    };
  };
}
