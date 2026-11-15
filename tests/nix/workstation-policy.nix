{ pkgs }:
let
  inherit (pkgs) lib;
  evaluate =
    overrides:
    lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        ../../hosts/nixos/desktop/local/workload-policy.nix
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.raw;
            default = [ ];
          };
          options.system.build = lib.mkOption {
            type = lib.types.attrsOf lib.types.package;
            default = { };
          };
          config.workstation.workloads = overrides;
        }
      ];
    };
  valid = result: lib.all (item: item.assertion) result.config.assertions;
  alternate = evaluate {
    aggregate = {
      memoryMiB = 8192;
      highMiB = 6144;
      swapMiB = 1024;
    };
    bounded = {
      minimumMiB = 2048;
      memoryMiB = 3072;
      maximumMiB = 5120;
      highPercent = 85;
      reserveMiB = 3072;
    };
    daemon = {
      memoryMiB = 6144;
      highMiB = 5120;
    };
  };
  hostConfig.workstation.workloads = alternate.config.workstation.workloads;
  systemModule = import ../../hosts/nixos/desktop/local/system.nix {
    config = hostConfig;
    inherit lib pkgs;
  };
  memoryModule = import ../../hosts/nixos/desktop/local/memory.nix {
    config = hostConfig;
    inherit lib pkgs;
  };
  invalid = map evaluate [
    {
      aggregate = {
        highMiB = 10240;
        memoryMiB = 10240;
      };
    }
    {
      bounded = {
        minimumMiB = 4096;
        memoryMiB = 2048;
      };
    }
    { bounded.maximumMiB = 11264; }
    { bounded.minimumMiB = 1536; }
    {
      daemon = {
        highMiB = 8192;
        memoryMiB = 8192;
      };
    }
  ];
in
assert valid alternate;
assert
  memoryModule.systemd.user.slices.background-workload.sliceConfig.MemoryMax == 8192 * 1024 * 1024;
assert
  memoryModule.systemd.user.slices.background-workload.sliceConfig.MemoryHigh == 6144 * 1024 * 1024;
assert systemModule.systemd.services.nix-daemon.serviceConfig.MemoryMax == 6144 * 1024 * 1024;
assert systemModule.systemd.services.nix-daemon.serviceConfig.MemoryHigh == 5120 * 1024 * 1024;
assert lib.all (result: !(valid result)) invalid;
pkgs.writeText "workstation-policy-invariants" "alternate policy accepted; invalid thresholds and allocations rejected\n"
