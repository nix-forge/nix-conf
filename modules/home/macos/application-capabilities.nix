{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.macos.applicationCapabilities;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  keyType = lib.types.strMatching "[a-zA-Z0-9][a-zA-Z0-9_.-]*";
  featureType = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "this application capability";
      service = lib.mkOption {
        type = lib.types.enum [
          "accessibility"
          "local-network"
          "camera"
          "microphone"
          "screen-recording"
          "input-monitoring"
          "full-disk-access"
          "apple-events"
          "notifications"
          "browser-integration"
          "protected-files"
          "background-items"
        ];
        description = "Capability to guide; declaring it never grants authorization.";
      };
      reason = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "Feature-specific justification.";
      };
      source = lib.mkOption {
        type = lib.types.strMatching "https://.+";
        description = "Primary evidence for the requirement.";
      };
      instruction = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = "How to test the feature in the actual application.";
      };
      minimumOS = lib.mkOption {
        type = lib.types.ints.between 13 99;
        default = 13;
        description = "Minimum macOS major version for this capability.";
      };
    };
  };
  apps = lib.filterAttrs (_: app: app.enable) cfg.apps;
  manifest = (pkgs.formats.json { }).generate "macos-application-capabilities.json" {
    schemaVersion = 1;
    appsDirectory = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
    stateDirectory = "${config.xdg.stateHome}/macos-readiness";
    apps = lib.mapAttrs (_: app: {
      inherit (app) bundle bundleId teamId;
      features = lib.mapAttrs (_: feature: {
        inherit (feature)
          service
          reason
          source
          instruction
          ;
        minimumOS = lib.max feature.minimumOS (if feature.service == "local-network" then 15 else 13);
      }) (lib.filterAttrs (_: feature: feature.enable) app.features);
    }) apps;
  };
  helper = pkgs.writers.writePython3Bin "hm-macos-readiness-helper" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./application_readiness.py;
  package = pkgs.writeShellApplication {
    name = "hm-macos-readiness";
    text = ''
      exec ${lib.getExe helper} --manifest ${manifest} "$@"
    '';
  };
in
{
  options.macos.applicationCapabilities = {
    enable =
      lib.mkEnableOption "personal macOS capability inventory and read-only readiness checks"
      // {
        default = isDarwin && config.targets.darwin.copyApps.enable;
      };
    manifest = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = manifest;
      description = "Generated selected-app capability manifest.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "Readiness and explicit guidance/verification command.";
    };
    apps = lib.mkOption {
      default = { };
      description = "Application identity expectations and opt-in feature requirements.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "this application's capability inventory";
            bundle = lib.mkOption {
              type = lib.types.strMatching "[^/]+\\.app";
              description = "Canonical copied top-level bundle name.";
            };
            bundleId = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "Expected installed CFBundleIdentifier.";
            };
            teamId = lib.mkOption {
              type = lib.types.nullOr lib.types.nonEmptyStr;
              default = null;
              description = "Expected vendor team, or null for applications without a team identity.";
            };
            features = lib.mkOption {
              type = lib.types.attrsOf featureType;
              default = { };
              description = "Capabilities selected by the application module or home profile.";
            };
          };
        }
      );
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isDarwin && config.targets.darwin.copyApps.enable;
        message = "macos.applicationCapabilities requires Darwin and canonical copied applications.";
      }
      {
        assertion = lib.all (key: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.-]*" key != null) (
          builtins.attrNames apps
        );
        message = "Application capability keys must be safe command identifiers.";
      }
      {
        assertion = lib.all (app: lib.all (key: keyType.check key) (builtins.attrNames app.features)) (
          builtins.attrValues apps
        );
        message = "Feature keys must be safe command identifiers.";
      }
      {
        assertion =
          lib.length (lib.unique (map (app: app.bundleId) (builtins.attrValues apps)))
          == lib.length (builtins.attrNames apps);
        message = "Application capability bundle identifiers must be unique.";
      }
      {
        assertion =
          lib.length (lib.unique (map (app: lib.toLower app.bundle) (builtins.attrValues apps)))
          == lib.length (builtins.attrNames apps);
        message = "Application capability bundle paths must be unique.";
      }
    ];
    home.packages = [ package ];
    xdg.configFile."macos/application-capabilities.json".source = manifest;
  };
}
