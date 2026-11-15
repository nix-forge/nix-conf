{
  config,
  lib,
  pkgs,
  ...
}:
let
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
        run ${lib.getExe pkgs.bash} ${./scripts/retire-unit-preview.sh} \
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
