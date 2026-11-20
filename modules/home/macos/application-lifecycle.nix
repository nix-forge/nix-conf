{
  config,
  lib,
  myLib,
  pkgs,
  inputs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cfg = config.macos.applications;
  appsDirectory = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  fixes = import ../../../overlays/temporary { inherit inputs lib; };
  helper = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).macosApplicationTools;
  manifest = pkgs.writeText "protected-macos-applications.json" (
    builtins.toJSON {
      inherit appsDirectory;
      inherit (cfg) manageAll;
      selectedApplications = "${
        pkgs.buildEnv {
          name = "selected-macos-applications";
          # Commands referring back to this manifest are installers, not app
          # inputs. Excluding them avoids a recursive derivation graph.
          # A package can also declare that it has no app bundles. Its CLI
          # still belongs to the home profile, outside the app inventory.
          paths = lib.filter (
            package:
            (package.hasMacOSApplications or true)
            && !(builtins.elem (lib.getName package) [
              "hm-macos-app-lifecycle"
              "macos-applications"
              "hm-macos-network-test"
            ])
          ) config.home.packages;
          pathsToLink = [ "/Applications" ];
        }
      }/Applications";
      localSigning = {
        inherit (cfg.localSigning) identity certificateSha256;
        keychain = "${config.home.homeDirectory}/Library/Keychains/login.keychain-db";
      };
      username = config.home.username;
      stateDirectory = "${config.xdg.stateHome}/macos-applications/lifecycle";
      queryScript = "${./scripts/application-paths.js}";
      rsync = lib.getExe pkgs.rsync;
      registryHelper = lib.getExe' cfg.registryHelperPackage "hm-macos-applications-helper";
      apps = lib.attrValues cfg.protectedApps;
    }
  );
  command = "${lib.getExe' helper "hm-macos-app-lifecycle-helper"} --manifest ${manifest}";
  monitor = pkgs.stdenv.mkDerivation {
    name = "macos-application-lifecycle-monitor";
    src = ./application-monitor.swift;
    networkProbe = ./network-probe.swift;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.swift ];
    buildPhase = ''
      swiftc -swift-version 5 -O "$src" -o monitor
      swiftc -swift-version 5 -O "$networkProbe" -o network-probe
    '';
    installPhase = ''mkdir -p "$out/bin"; cp monitor "$out/bin/hm-macos-app-monitor"; cp network-probe "$out/bin/hm-macos-network-probe"'';
  };
  enabled = cfg.enable && (cfg.manageAll || cfg.protectedBundles != [ ]);
in
{
  imports = [
    (fixes.apply "home-manager-app-management-consent" {
      upstream = inputs.home-manager;
      replacement = fixes.apply "home-manager-protected-apps" inputs.home-manager;
    })
  ];
  options.macos.applications = {
    manageAll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Transactionally manage every top-level app selected by home.packages; preserve certificate signatures and locally sign ad-hoc/unsigned apps.";
    };
    localSigning = {
      identity = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "Nix Local Applications";
        description = "Persistent Code Signing certificate name in the login Keychain. Create it once, then explicitly enroll it using the lifecycle command.";
      };
      certificateSha256 = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[a-fA-F0-9]{64}");
        default = null;
        description = "Optional public certificate pin. Without it, explicit enrollment pins the certificate in private local state; activation never generates or changes keys.";
      };
    };
    registryHelperPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).macosApplicationTools;
      description = "Native registration inventory and scoped reconciliation helper.";
    };
    protectedApps = lib.mkOption {
      default = { };
      description = "Vendor-signed apps copied transactionally, with running identity and downgrade guards.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            bundle = lib.mkOption { type = lib.types.strMatching "[^/]+\\.app"; };
            bundleId = lib.mkOption { type = lib.types.nonEmptyStr; };
            teamId = lib.mkOption { type = lib.types.nonEmptyStr; };
            source = lib.mkOption {
              type = lib.types.str;
              description = "Absolute selected package bundle path.";
            };
            previousBundles = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "[^/]+\\.app");
              default = [ ];
              description = "Previous canonical names to retire only after vendor verification and a full application quit; complete bundles are retained privately.";
            };
          };
        }
      );
    };
    protectedBundles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = lib.concatMap (app: [ app.bundle ] ++ app.previousBundles) (
        lib.attrValues cfg.protectedApps
      );
      description = "Bundles excluded from Home Manager's in-place rsync.";
    };
    lifecyclePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = writeShellApplication {
        name = "hm-macos-app-lifecycle";
        text = ''exec ${command} "$@"'';
      };
      description = "Configured protected-app preflight, transaction, and health checker.";
    };
  };
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion =
          lib.length cfg.protectedBundles == lib.length (lib.unique (map lib.toLower cfg.protectedBundles));
        message = "Protected app bundles must have distinct case-insensitive names.";
      }
      {
        assertion = lib.all (
          app:
          baseNameOf app.source == app.bundle || builtins.elem (baseNameOf app.source) app.previousBundles
        ) (lib.attrValues cfg.protectedApps);
        message = "A renamed protected application must exclude and retire its original source bundle name.";
      }
    ];
    home.packages = [
      cfg.lifecyclePackage
    ]
    ++ lib.optional (cfg.protectedApps ? codex) (writeShellApplication {
      name = "hm-macos-network-test";
      text = ''
        exec ${
          lib.getExe' (import ../../../flake/runtime-packages.nix { inherit pkgs; }).macosApplicationTools
            "hm-macos-network-test"
        } \
          --app ${lib.escapeShellArg (appsDirectory + "/" + cfg.protectedApps.codex.bundle)} \
          --lifecycle ${lib.getExe cfg.lifecyclePackage} \
          --probe ${monitor}/bin/hm-macos-network-probe "$@"
      '';
    });
    home.activation = {
      preflightProtectedApps = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        ${command} --mode preflight
      '';
      installProtectedApps = lib.hm.dag.entryBetween [ "reconcileDarwinApplications" ] [ "copyApps" ] ''
        run ${command} --mode install
      '';
    };
    launchd.agents.macos-application-lifecycle = {
      enable = true;
      config = {
        ProgramArguments = [
          "${monitor}/bin/hm-macos-app-monitor"
          appsDirectory
          (lib.getExe cfg.lifecyclePackage)
          "--mode"
          "observe"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        LimitLoadToSessionType = [ "Aqua" ];
        StandardOutPath = "${config.xdg.stateHome}/macos-applications/lifecycle/monitor.log";
        StandardErrorPath = "${config.xdg.stateHome}/macos-applications/lifecycle/monitor-errors.log";
      };
    };
  };
}
