{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  deploymentChecksBySystem.x86_64-linux = inputs.deploy-rs.lib.x86_64-linux.deployChecks self.deploy;
in
{
  flake = {
    deploy.nodes.desktop = {
      hostname = "desktop";
      sshUser = "root";
      # Keep the full desktop closure off the Mac's native Linux builder.
      # deploy-rs evaluates locally, then asks the desktop to build and activate.
      remoteBuild = true;
      activationTimeout = 600;
      confirmTimeout = 120;

      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.desktop;
      };
    };

    # Full deployment checks build the desktop closure and belong on that host.
    # Derive exclusions from their owner so new ordinary checks still enter CI.
    ciChecks = lib.mapAttrs (
      system: checks:
      removeAttrs checks (
        builtins.attrNames (
          (deploymentChecksBySystem.${system} or { }) // (self.lintChecks.${system} or { })
        )
      )
    ) self.checks;

    checks.x86_64-linux = deploymentChecksBySystem.x86_64-linux // {
      # Building the wrapped browser is the regression test. The defect was in
      # package construction, not in a host option value.
      zen-wrapper-copy-regression =
        self.nixosConfigurations.desktop.config.home-manager.users.ianmh.programs.zen-browser.package;
    };
  };
}
