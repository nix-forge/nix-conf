{ config, lib, ... }:
let
  cfg = config.workstation.memoryEfficiency.java;
  flags =
    name:
    let
      service = cfg.services.${name};
    in
    lib.optionals service.enable (
      lib.optional (service.minimumHeapMiB != null) "-Xms${toString service.minimumHeapMiB}m"
      ++ [
        "-XX:G1PeriodicGCInterval=${toString (cfg.idleCollectionIntervalSeconds * 1000)}"
        "-XX:+G1PeriodicGCInvokesConcurrent"
        "-XX:G1PeriodicGCSystemLoadThreshold=${toString cfg.idleCollectionLoadThreshold}"
      ]
      ++ lib.optional service.compactObjectHeaders "-XX:+UseCompactObjectHeaders"
    );
in
{
  options.workstation.memoryEfficiency.java = {
    idleCollectionIntervalSeconds = lib.mkOption {
      type = lib.types.ints.between 0 3600;
      default = 300;
      description = "G1 idle heap return interval; zero disables periodic collection. Maximum heap sizes remain application-owned.";
    };
    idleCollectionLoadThreshold = lib.mkOption {
      type = lib.types.ints.between 0 256;
      default = 4;
      description = "Skip periodic G1 collection above this one-minute host load; zero disables the load check.";
    };
    services = lib.genAttrs [ "komga" "stirling-pdf" ] (
      name:
      lib.mkOption {
        default = { };
        description = "Heap efficiency controls for ${name}.";
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable the chosen minimum heap and concurrent idle heap return.";
            };
            minimumHeapMiB = lib.mkOption {
              type = lib.types.nullOr (lib.types.ints.between 16 512);
              default = if name == "stirling-pdf" then 64 else null;
              description = "Initial and minimum Java heap in MiB; null preserves JVM ergonomics. Not a maximum or native-memory limit.";
            };
            compactObjectHeaders = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Opt into compact object headers on the Java 25 services after workload validation.";
            };
          };
        };
      }
    );
  };

  config = {
    lib.desktopJavaMemory.flags = flags;
    systemd.services = {
      komga = lib.mkIf config.services.komga.enable {
        environment.JAVA_TOOL_OPTIONS = lib.concatStringsSep " " (flags "komga");
      };
    };
  };
}
