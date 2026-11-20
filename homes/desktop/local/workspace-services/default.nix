{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  retirePreview = pkgs.writeText "retire-unit-preview.sh" (
    myLib.writers.checkedShellText { inherit pkgs; } {
      name = "retire-unit-preview";
      text = ''
        #!/usr/bin/env bash
        # Retire this scoped repair only after the managed generation links its units.
        set -euo pipefail

        config_home=$1
        state_home=$2
        preview="$config_home/systemd/user.control/workspace-edge.service"
        target="$state_home/workspace-services/unit-preview/workspace-edge.service"
        if [[ -L $preview && "$(readlink -- "$preview")" == "$target" ]]; then
          rm -- "$preview"
        fi

        for name in api worker dashboard edge; do
          override="$config_home/systemd/user/workspace-$name.service.d/90-runtime-recovery.conf"
          if [[ -f $override && ! -L $override ]] &&
            cmp -s -- "$override" <(printf '[Service]\nPrivateTmp=no\n'); then
            rm -- "$override"
          fi
        done
      '';
    }
  );
  runtime = config.lib.workspaceServices.mkRuntime {
    inherit pkgs;
    configPath = "${config.xdg.configHome}/workspace-services/private.json";
  };
in
{
  home.packages = [ runtime.package ];
  # A scoped repair can replace a complete dependency list before the next
  # generation is built. Retire only our exact preview after managed units link.
  home.activation.retireWorkspaceServicePreview =
    lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ]
      ''
        run ${lib.getExe pkgs.bash} ${retirePreview} \
          ${lib.escapeShellArg config.xdg.configHome} ${lib.escapeShellArg config.xdg.stateHome}
      '';
  xdg.configFile =
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "systemd/user/${name}" {
        source = "${runtime.package}/share/systemd/user/${name}";
        force = true;
      }
    ) runtime.units
    // {
      "systemd/user/default.target.wants/workspace.target" = {
        source = "${runtime.package}/share/systemd/user/workspace.target";
        force = true;
      };
      "systemd/user/timers.target.wants/workspace-backup.timer" = {
        source = "${runtime.package}/share/systemd/user/workspace-backup.timer";
        force = true;
      };
    };
}
