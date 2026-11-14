{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  network = builtins.fromJSON (builtins.readFile ../network.json);
  # The upstream Darwin activator embeds its own deploy-rs executable. Select
  # the host's guarded Darwin package fix there as well as in the home profile.
  deployDarwinPkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    overlays = [
      inputs.deploy-rs.overlays.default
      (_: prev: {
        deploy-rs = prev.deploy-rs // {
          deploy-rs = self.darwinConfigurations.macbook-pro-m4.pkgs.deploy-rs;
        };
      })
    ];
  };
  deployDarwinLib = deployDarwinPkgs.deploy-rs.lib;
  deploymentChecksBySystem.x86_64-linux = inputs.deploy-rs.lib.x86_64-linux.deployChecks (
    self.deploy // { nodes = removeAttrs self.deploy.nodes [ "macbook-pro-m4" ]; }
  );
  deploymentChecksBySystem.aarch64-darwin = deployDarwinLib.deployChecks (
    self.deploy // { nodes = { inherit (self.deploy.nodes) macbook-pro-m4; }; }
  );
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
    "public-demo-runtime"
    "sentry-crashpad-lock"
    "service-command-arguments"
    "virtualisation-generated-artifacts"
    "zen-wrapper-copy-regression"
  ];
in
{
  flake = {
    deploy.nodes.raspberry-pi = {
      hostname = network.raspberryPiServerAddress;
      sshUser = "root";
      # A persistent local SSH master can keep workstation-task's queue occupied
      # after deploy-rs exits. Use short-lived connections for this node.
      sshOpts = [
        "-o"
        "ControlMaster=no"
      ];
      # Build natively when the desktop matches the Pi, otherwise cross-compile, then
      # transfer completed outputs over authenticated SSH. The Pi only activates.
      remoteBuild = false;
      # Copy the built closure directly. Destination substitution can pull
      # inputs from caches that the Pi intentionally does not trust.
      fastConnection = true;
      activationTimeout = 300;
      confirmTimeout = 120;
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos (
          self.lib.nixosConfigurationFor {
            name = "raspberry-pi";
            buildSystem = self.nixosConfigurations.desktop.pkgs.stdenv.hostPlatform.system;
          }
        );
      };
    };

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

    deploy.nodes.macbook-pro-m4 = {
      hostname = "macbook";
      sshUser = "root";
      # The existing macbook alias supplies the desktop key and pinned host
      # key. sshUser selects root over that alias's ordinary user default.
      remoteBuild = true;
      activationTimeout = 600;
      # deploy-rs's confirmation watcher does not observe canary removal on
      # Darwin. Keep rollback on activation errors, without the timed watcher.
      magicRollback = false;

      profiles.system = {
        user = "root";
        path = deployDarwinLib.activate.darwin self.darwinConfigurations.macbook-pro-m4;
      };
    };

    # Full deployment checks build each host's closure and belong on that host.
    # Derive exclusions from their owner so new ordinary checks still enter CI.
    ciChecks = lib.mapAttrs (
      system: checks:
      let
        selected = removeAttrs checks (
          aggregateChecks
          ++ hostedRunnerExclusions
          ++ lib.optionals (system != "x86_64-linux") oncePerRevision
          ++ lib.optionals (system == "aarch64-linux") linuxOncePerRevision
          ++ builtins.attrNames (
            (deploymentChecksBySystem.${system} or { }) // (self.lintChecks.${system} or { })
          )
        );
        # Both consumers require the desktop's repaired Determinate runtime and
        # its complete upstream suites. Share that build on one ephemeral runner.
        sharedRuntimeChecks = [
          "desktop-workload"
          "nix-credential-loading"
        ];
        ciPkgs = import inputs.nixpkgs { inherit system; };
      in
      if system == "x86_64-linux" then
        assert builtins.all (name: builtins.hasAttr name selected) sharedRuntimeChecks;
        assert !(selected ? determinate-runtime-consumers);
        removeAttrs selected sharedRuntimeChecks
        // {
          determinate-runtime-consumers = ciPkgs.linkFarm "determinate-runtime-consumers" (
            map (name: {
              inherit name;
              path = selected.${name};
            }) sharedRuntimeChecks
          );
        }
      else
        selected
    ) self.checks;

    checks.x86_64-linux = deploymentChecksBySystem.x86_64-linux // {
      # Building the wrapped browser is the regression test. The defect was in
      # package construction, not in a host option value.
      zen-wrapper-copy-regression =
        self.nixosConfigurations.desktop.config.home-manager.users.ianmh.programs.zen-browser.package;
    };
    checks.aarch64-darwin = deploymentChecksBySystem.aarch64-darwin;
  };

  perSystem = { pkgs, ... }: {
    packages.deploy-rs = inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
