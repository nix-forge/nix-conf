{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  darwinPkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
  app = {
    enable = lib.mkDefault true;
    bundle = "Example App.app";
    bundleId = "org.example.app";
    features.lan = {
      enable = true;
      service = "local-network";
      reason = "Connect to a selected LAN service";
      source = "https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy";
      instruction = "Use the real GUI app to connect to a selected service.";
    };
  };
  home =
    platformPkgs: extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = platformPkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ../../modules/home/macos/application-capabilities.nix
        {
          home = {
            username = "capability-test";
            homeDirectory = "/tmp/capability-test";
            stateVersion = "25.05";
          };
          targets.darwin.copyApps.enable = platformPkgs.stdenv.hostPlatform.isDarwin;
          targets.darwin.linkApps.enable = false;
          macos.applicationCapabilities.apps.example = app;
        }
        extra
      ];
    };
  selected = home darwinPkgs { };
  disabled = home darwinPkgs { macos.applicationCapabilities.apps.example.enable = false; };
  noFeature = home darwinPkgs {
    macos.applicationCapabilities.apps.example.features.lan.enable = lib.mkForce false;
  };
  linux = home (import inputs.nixpkgs { system = "x86_64-linux"; }) { };
  valid = item: lib.all (a: a.assertion) item.config.assertions;
  withLaunchers = home darwinPkgs {
    imports = [ ../../modules/home/macos/applications.nix ];
    macos.applications.commands.example = {
      bundle = "Example App.app";
      executable = "";
    };
    macos.applications.commands.cli = {
      bundle = "Example App.app";
      executable = "Contents/MacOS/example";
    };
  };
  protected = home darwinPkgs {
    imports = [ ../../modules/home/macos/applications.nix ];
    macos.applications.protectedApps.example = {
      bundle = "Example App.app";
      bundleId = "org.example.app";
      teamId = "EXAMPLE";
      source = "/nix/store/fixture/Applications/Example App.app";
    };
  };
  withMonitor = home darwinPkgs {
    imports = [ ../../modules/home/vorssaint.nix ];
    programs.vorssaint = {
      enable = true;
      package = (darwinPkgs.writeShellScriptBin "monitor-fixture" "exit 0") // {
        appName = "PersonalMonitor";
      };
      acknowledgeFanControlLimitation = true;
    };
  };
  duplicate = home darwinPkgs { macos.applicationCapabilities.apps.other = app; };
  caseCollision = home darwinPkgs {
    macos.applicationCapabilities.apps.other = app // {
      bundle = "example app.app";
      bundleId = "org.example.other";
    };
  };
  unsupported = home darwinPkgs {
    macos.applicationCapabilities.apps.example.features.lan.service = lib.mkForce "silent-grant";
  };
  managed = home darwinPkgs {
    macos.applicationCapabilities.apps.example.features.lan.delivery = "pppc";
  };
  invalidKey = home darwinPkgs {
    macos.applicationCapabilities.apps."../outside" = app // {
      bundleId = "org.example.other";
      bundle = "Other.app";
    };
  };
  # Inspect the actual JSON generator input without import-from-derivation.
  # The native command build separately exercises the generated file.
  manifest = item: item.config.macos.applicationCapabilities.manifest.value;
in
assert valid selected;
assert valid disabled;
assert valid noFeature;
assert valid withLaunchers;
assert valid protected;
assert lib.hasInfix "--exclude='/Example App.app'" protected.config.home.activation.copyApps.data;
assert builtins.elem "writeBoundary" protected.config.home.activation.preflightProtectedApps.before;
assert builtins.elem "copyApps" protected.config.home.activation.installProtectedApps.after;
assert protected.config.launchd.agents.macos-application-lifecycle.config.RunAtLoad;
assert
  lib.last protected.config.launchd.agents.macos-application-lifecycle.config.ProgramArguments
  == "observe";
assert !linux.config.launchd.enable;
assert withLaunchers.config.macos.applications.commands.example.executable == "";
assert withLaunchers.config.macos.applications.commands.cli.executable == "Contents/MacOS/example";
assert (manifest withMonitor).apps ? vorssaint;
assert !(withMonitor.config.launchd.agents.vorssaint.config ? macos);
assert !(builtins.tryEval duplicate.config.home.activationPackage.drvPath).success;
assert !(builtins.tryEval caseCollision.config.home.activationPackage.drvPath).success;
assert !(builtins.tryEval invalidKey.config.home.activationPackage.drvPath).success;
assert !(builtins.tryEval unsupported.config.home.activationPackage.drvPath).success;
assert !(builtins.tryEval managed.config.home.activationPackage.drvPath).success;
assert !linux.config.macos.applicationCapabilities.enable;
assert !(linux.config.xdg.configFile ? "macos/application-capabilities.json");
assert (manifest disabled).apps == { };
assert (manifest noFeature).apps.example.features == { };
assert (manifest selected).apps.example.features.lan.minimumOS == 15;
assert (manifest selected).apps.example.bundle == "Example App.app";
pkgs.runCommand "macos-application-capabilities" { } "touch $out"
