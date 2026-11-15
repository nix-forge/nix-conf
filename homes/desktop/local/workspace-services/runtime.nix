{ lib, ... }: {
  lib.workspaceServices.mkRuntime =
    { pkgs, configPath }:
    let
      tools = {
        python = pkgs.python314;
        inherit (pkgs) uv;
        node = pkgs.nodejs_24;
        corepack = pkgs.corepack_24;
        database = pkgs.postgresql_18;
        library = pkgs.stdenv.cc.cc.lib;
        compression = pkgs.zlib;
        crypto = pkgs.openssl.bin;
        edge = pkgs.caddy;
      };
      toolPaths = pkgs.writeText "workspace-tools.json" (
        builtins.toJSON (lib.mapAttrs (_: toString) tools)
      );
      runner = pkgs.writeShellApplication {
        name = "workspace";
        runtimeInputs = [
          pkgs.bash
          pkgs.systemd
          pkgs.coreutils
          tools.uv
          tools.node
          tools.corepack
        ];
        text = (import ../../../../lib/templates/text.nix) ./scripts/workspace.sh {
          inherit toolPaths;
          privateConfig = lib.escapeShellArg configPath;
          lib_getExe_tools_python = lib.getExe tools.python;
          runner_py = ./runner.py;
        };
      };
      executable = lib.getExe runner;
      common = ''
        Restart=on-failure
        RestartSec=3s
        UMask=0077
        NoNewPrivileges=yes
        # User-service mount isolation remaps host root ownership. Private
        # adapters must see real ancestor owners when validating credential paths.
        PrivateTmp=no
        CPUWeight=50
        IOWeight=50
        TimeoutStopSec=60s
      '';
      service = name: extra: ''
        [Unit]
        Description=Local workspace ${name}
        PartOf=workspace.target
        ${lib.optionalString (
          name != "database"
        ) "Requires=workspace-database.service\nAfter=workspace-database.service"}
        ${lib.optionalString (name == "edge")
          # Keep retrying the edge's readiness check if an upstream initially
          # fails. Requires would cancel its start job without a restart.
          "Wants=workspace-api.service workspace-dashboard.service\nAfter=workspace-api.service workspace-dashboard.service"
        }
        [Service]
        Type=${if name == "database" then "notify" else "simple"}
        ExecStart=${executable} service ${name}
        ${common}
        ${extra}
      '';
      units = {
        "workspace.target" = ''
          [Unit]
          Description=Local workspace services
          Wants=workspace-database.service workspace-api.service workspace-worker.service workspace-dashboard.service workspace-edge.service
          After=workspace-database.service
          [Install]
          WantedBy=default.target
        '';
        "workspace-database.service" = service "database" ''
          KillSignal=SIGINT
          KillMode=mixed
          MemoryHigh=1G
          MemoryMax=2G
          CPUQuota=100%
          TimeoutStartSec=180s
        '';
        "workspace-api.service" = service "api" ''
          ExecStartPost=${executable} health api
          MemoryHigh=2G
          MemoryMax=3G
          CPUQuota=200%
        '';
        "workspace-worker.service" = service "worker" ''
          MemoryHigh=2G
          MemoryMax=3G
          CPUQuota=200%
        '';
        "workspace-dashboard.service" = service "dashboard" ''
          ExecStartPost=${executable} health dashboard
          MemoryHigh=512M
          MemoryMax=1G
          CPUQuota=100%
        '';
        "workspace-edge.service" = service "edge" ''
          ExecStartPost=${executable} health edge
          MemoryHigh=256M
          MemoryMax=512M
        '';
        "workspace-backup.service" = ''
          [Unit]
          Description=Local workspace snapshot
          # Timer jobs may wait for the build queue held by activation. Let the
          # current job finish without restarting or awaiting it during a switch.
          X-SwitchMethod=keep-old
          Requires=workspace-database.service
          After=workspace-database.service
          [Service]
          Type=oneshot
          ExecStart=${executable} backup-job
          UMask=0077
          NoNewPrivileges=yes
          CPUWeight=20
          IOWeight=20
        '';
        "workspace-backup.timer" = ''
          [Unit]
          Description=Daily local workspace snapshot
          [Timer]
          OnCalendar=daily
          Persistent=yes
          RandomizedDelaySec=15m
          [Install]
          WantedBy=timers.target
        '';
      };
      files = lib.mapAttrs (name: text: pkgs.writeText name text) units;
      package = pkgs.symlinkJoin {
        name = "workspace-services";
        paths = [ runner ];
        postBuild = (import ../../../../lib/templates/text.nix) ./scripts/workspace-services.sh {
          lib_concatStringsSep_n_lib_mapAttrsToList_name_file_ln_s_fil = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: file: ''ln -s ${file} "$out/share/systemd/user/${name}"'') files
          );
        };
      };
    in
    {
      inherit package units;
    };

}
