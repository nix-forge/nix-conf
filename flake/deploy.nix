{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  deploymentChecksBySystem.x86_64-linux = inputs.deploy-rs.lib.x86_64-linux.deployChecks self.deploy;
  # These checks already evaluate every supported target from one derivation.
  # Running them again in the ARM and Darwin jobs only repeats the same flake
  # evaluation with a different runCommand shell.
  oncePerRevision = [
    "cache-policy"
    "git-email-privacy"
    "platform-contracts"
    "secret-templates"
    "temporary-package-fixes"
  ];
  # Python behavior tests are platform-independent and do not need to run on
  # both Linux architectures. Keep one Linux copy and retain the Darwin copy
  # so the separate native environment still exercises the shared test tree.
  linuxOncePerRevision = [ "python-tests" ];
  # This link farm is a local convenience target over checks that CI builds by
  # name. Evaluating it in CI duplicates the slowest part of check discovery.
  aggregateChecks = [ "generated-artifacts" ];
  # These checks validate the concrete desktop workstation, run VM-backed
  # integration tests, or build large workstation closures. Generic hosted
  # runners are the wrong owner: run them on the desktop with the dedicated
  # validation recipes or build the check explicitly when changing the
  # corresponding subsystem.
  hostedRunnerExclusions = [
    "application-recovery"
    "clamav-runtime"
    "desktop-authentication"
    "desktop-commands"
    "desktop-iocost"
    "desktop-memory-policy"
    "desktop-storage-install"
    "public-demo-runtime"
    "sentry-crashpad-lock"
    "service-command-arguments"
    "virtualisation-generated-artifacts"
    "zen-wrapper-copy-regression"
  ];
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
        aggregateChecks
        ++ hostedRunnerExclusions
        ++ lib.optionals (system != "x86_64-linux") oncePerRevision
        ++ lib.optionals (system == "aarch64-linux") linuxOncePerRevision
        ++ builtins.attrNames (
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
