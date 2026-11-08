{
  inputs,
  pkgs,
  myLib,
}:
let
  inherit (pkgs) lib;
  inherit (import ./module-fixtures.nix { inherit inputs pkgs myLib; })
    homeFor
    systemFor
    valid
    rejects
    ;
  linux = pkgs.stdenv.hostPlatform.isLinux;
  sshModule = ../../modules/home/services/ssh-forwards.nix;
  identityModule = ../../modules/home/dev/jj-identity.nix;
  forward = {
    host = "builder.example.test";
    bindPort = 8443;
    targetPort = 9443;
  };
  ssh =
    settings:
    homeFor [
      sshModule
      { services.sshForwards.fixture = forward // settings; }
    ];
  disabled = homeFor [
    sshModule
    identityModule
  ];
  enabled = ssh { };
  exposed = ssh { bindAddress = "0.0.0.0"; };
  remote = ssh {
    direction = "remote";
    targetAddress = "::1";
  };
  collision = homeFor [
    sshModule
    {
      services.sshForwards = {
        first = forward;
        second = forward;
      };
    }
  ];
  identity = homeFor [
    identityModule
    {
      programs.jujutsu.runtimeIdentity = {
        enable = true;
        sourceFile = "/run/credentials/identity";
      };
    }
  ];
  fallback = homeFor [
    identityModule
    { programs.jujutsu.runtimeIdentity.enable = true; }
  ];
  invalidIdentity = homeFor [
    identityModule
    {
      programs.jujutsu.runtimeIdentity = {
        enable = true;
        sourceFile = "/nix/store/identity";
      };
    }
  ];
  sshArgs =
    if linux then
      (lib.concatStringsSep " " enabled.systemd.user.services.fixture.Service.ExecStart)
    else
      lib.concatStringsSep " " enabled.launchd.agents.fixture.config.ProgramArguments;
  remoteArgs =
    if linux then
      (lib.concatStringsSep " " remote.systemd.user.services.fixture.Service.ExecStart)
    else
      lib.concatStringsSep " " remote.launchd.agents.fixture.config.ProgramArguments;
  rust = homeFor [ ../../modules/home/vscode/languages/rust.nix ];
  rustOverride = homeFor [
    ../../modules/home/vscode/languages/rust.nix
    ../../modules/home/vscode/default.nix
    {
      programs.vscode.rust = {
        allTargets = false;
        denyWarnings = true;
      };
      programs.vscode.profiles.default.userSettings."rust-analyzer.check.command" = "check";
    }
  ];
  activation =
    settings:
    systemFor [
      ../../modules/nixos/system/activation-safety.nix
      settings
    ];
  iocost =
    settings:
    systemFor [
      ../../modules/nixos/hardware/iocost.nix
      settings
    ];
  iwd =
    settings:
    systemFor [
      ../../modules/nixos/network/iwd-profiles.nix
      settings
    ];
  wifi = iwd {
    networking.wireless.iwd.runtimeProfiles.fixture.source = "/run/credentials/wifi%profile";
  };
  report = {
    rustOwnsEditor =
      valid rust
      && rust.programs.vscode.enable
      && rust.programs.vscode.profiles.default.userSettings."rust-analyzer.check.command" == "clippy";
    rustDoesNotImposeWarningPolicy =
      rust.programs.vscode.profiles.default.userSettings."rust-analyzer.check.extraArgs" == [ ];
    rustComposesAndAllowsOverrides =
      valid rustOverride
      &&
        rustOverride.programs.vscode.profiles.default.userSettings."rust-analyzer.check.command" == "check"
      && !rustOverride.programs.vscode.profiles.default.userSettings."rust-analyzer.check.allTargets"
      &&
        rustOverride.programs.vscode.profiles.default.userSettings."rust-analyzer.check.extraArgs" == [
          "--"
          "-D"
          "warnings"
        ];
    disabledHasNoUnits =
      !(disabled.systemd.user.services ? fixture)
      && !(disabled.launchd.agents ? fixture)
      && !(disabled.home.activation ? jujutsuLocalIdentity)
      && !disabled.programs.jujutsu.enable;
    managerOwnsReconnects =
      valid enabled
      && (
        if linux then
          enabled.systemd.user.services.fixture.Service.Restart == "always"
        else
          enabled.launchd.agents.fixture.config.KeepAlive
      );
    verifiesHostIdentity =
      lib.hasInfix "StrictHostKeyChecking=yes" sshArgs && lib.hasInfix "ExitOnForwardFailure=yes" sshArgs;
    independentForegroundSession =
      lib.hasInfix "ControlPath=none" sshArgs && lib.hasInfix "ForkAfterAuthentication=no" sshArgs;
    exposureRequiresAcknowledgment =
      rejects "acknowledgeExposure" exposed
      && valid (ssh {
        bindAddress = "0.0.0.0";
        acknowledgeExposure = true;
      });
    duplicateListenersRejected = rejects "distinct listener" collision;
    unsafeHostRejected = rejects "single destination" (ssh {
      host = "-oProxyCommand=bad";
    });
    ipv6IsBracketed = valid remote && lib.hasInfix "127.0.0.1:8443:[::1]:9443" remoteArgs;
    sourceIdentityNeedsNoGit =
      valid identity && identity.programs.jujutsu.enable && !identity.programs.git.enable;
    fallbackRequiresGit = rejects "programs.git.enable" fallback;
    identityRejectsStoreSource = rejects "outside the Nix store" invalidIdentity;
    systemdArgumentsAreLiteral =
      (import ../../lib/systemd/exec-args.nix) [
        "a b"
        "100%"
        "$VALUE"
        "quote\""
      ] == ''"a b" "100%%" "$$VALUE" "quote\""'';
  }
  // lib.optionalAttrs linux {
    activationDisabledIsEmpty =
      !((activation { }).system.preSwitchChecks ? updateDiff)
      && !((activation { }).system.preSwitchChecks ? expectedHostname);
    activationRejectsUnnamedHost = rejects "nonempty networking.hostName" (activation {
      system.activationSafety.enable = true;
      networking.hostName = "";
    });
    activationUsesConfiguredHost = valid (activation {
      system.activationSafety.enable = true;
      networking.hostName = "fixture";
    });
    ioCostDisabledHasNoUnits = !((iocost { }).systemd.services ? adaptive-iocost);
    ioCostRequiresSelection = rejects "explicit, safe" (iocost {
      hardware.ioCost.enable = true;
    });
    ioCostAcceptsNativeGlobs = valid (iocost {
      hardware.ioCost = {
        enable = true;
        kernelDevicePatterns = [ "nvme[0-9]*n[0-9]*" ];
      };
    });
    ioCostRejectsRuleInjection = rejects "explicit, safe" (iocost {
      hardware.ioCost = {
        enable = true;
        kernelDevicePatterns = [ ''nvme*", RUN+="bad'' ];
      };
    });
    iwdDisabledHasNoProfileUnit = !((iwd { }).systemd.services ? iwd-fixture-profile);
    iwdOwnsIntrinsicDependency = valid wifi && wifi.networking.wireless.iwd.enable;
    iwdDoesNotImposeNetworkManager =
      !wifi.networking.networkmanager.enable && !wifi.systemd.network.enable;
    iwdEscapesSpecifier =
      wifi.systemd.services.iwd-fixture-profile.unitConfig.ConditionPathExists
      == "/run/credentials/wifi%%profile";
    iwdRejectsDaemonOrderingCycle = rejects "must not depend" (iwd {
      networking.wireless.iwd.runtimeProfiles.fixture = {
        source = "/run/credentials/wifi";
        afterUnits = [ "iwd.service" ];
      };
    });
    iwdRejectsSelfOrderingCycle = rejects "must not depend" (iwd {
      networking.wireless.iwd.runtimeProfiles.fixture = {
        source = "/run/credentials/wifi";
        afterUnits = [ "iwd-fixture-profile.service" ];
      };
    });
    iwdRejectsStoreCredentials = rejects "outside the Nix store" (iwd {
      networking.wireless.iwd.runtimeProfiles.fixture.source = "/nix/store/credentials";
    });
    iwdRejectsDisabledDaemon = rejects "require networking.wireless.iwd.enable" (iwd {
      networking.wireless.iwd.runtimeProfiles.fixture.source = "/run/credentials/wifi";
      networking.wireless.iwd.enable = lib.mkForce false;
    });
  };
in
assert lib.assertMsg (lib.all (value: value) (lib.attrValues report)) (
  "Local feature contracts failed: " + builtins.toJSON report
);
pkgs.runCommand "local-feature-reuse" {
  report = builtins.toJSON report;
  passAsFile = [ "report" ];
} ''cp "$reportPath" "$out"''
