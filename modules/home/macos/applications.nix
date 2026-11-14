{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.macos.applications;
  appsDirectory = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  render = import ../../../lib/templates/text.nix;
  manager = cfg.registryHelperPackage;
  managerArgs = lib.escapeShellArgs [
    "--apps-dir"
    appsDirectory
    "--legacy-dir"
    "${config.home.homeDirectory}/Applications"
    "--state-dir"
    "${config.xdg.stateHome}/macos-applications/recovery.noindex"
    "--query-script"
    "${./scripts/application-paths.js}"
  ];
  commands = lib.mapAttrsToList (
    name: command:
    pkgs.writeShellApplication {
      inherit name;
      text = render ./scripts/launch-managed-app.sh.in {
        app = lib.escapeShellArg "${appsDirectory}/${command.bundle}";
        executable = lib.escapeShellArg (command.executable or "");
        open = "/usr/bin/open";
      };
    }
  ) cfg.commands;
  commandAliases = lib.concatLists (
    lib.mapAttrsToList (
      name: command: map (alias: { inherit name alias; }) command.aliases
    ) cfg.commands
  );
  package = pkgs.symlinkJoin {
    name = "macos-applications";
    paths = commands ++ [
      (pkgs.writeShellApplication {
        name = "hm-macos-applications";
        text = render ./scripts/reconcile-applications.sh.in {
          lifecycleCheck = lib.optionalString (cfg.protectedBundles != [ ]) ''
            if [[ " ''${*} " == *" --check "* ]]; then
              ${lib.getExe cfg.lifecyclePackage} --mode check || exit "$?"
            fi
          '';
          helper = lib.getExe manager;
          args = managerArgs;
        };
      })
    ];
    postBuild = lib.concatMapStringsSep "\n" (
      item:
      render ./scripts/link-command-alias.sh.in {
        name = lib.escapeShellArg item.name;
        alias = lib.escapeShellArg item.alias;
      }
    ) commandAliases;
    meta.mainProgram = "hm-macos-applications";
  };
in
{
  imports = [ ./application-lifecycle.nix ];
  options.macos.applications = {
    enable = lib.mkEnableOption "canonical copied macOS applications and launch paths" // {
      default = pkgs.stdenv.hostPlatform.isDarwin && config.targets.darwin.copyApps.enable;
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "Canonical launchers and the configured application registration command.";
    };
    commands = lib.mkOption {
      default = { };
      description = "GUI launch commands that must use the copied Home Manager app bundles.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            aliases = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9+_.-]*");
              default = [ ];
              description = "Additional command names, created only when the filesystem treats them as distinct.";
            };
            bundle = lib.mkOption {
              type = lib.types.strMatching "[^/]+\\.app";
              description = "Top-level application bundle name in the copied application directory.";
            };
            executable = lib.mkOption {
              type = lib.types.strMatching "(Contents/[^.].*)?";
              default = "";
              description = ''
                Native CLI path relative to the bundle. Empty uses Launch Services
                to open the application and reuse its running instance.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin && config.targets.darwin.copyApps.enable;
        message = "macos.applications requires Darwin and targets.darwin.copyApps.enable.";
      }
      {
        assertion = builtins.all (
          item: !(builtins.elem item.alias ((builtins.attrNames cfg.commands) ++ [ "hm-macos-applications" ]))
        ) commandAliases;
        message = "macos.applications command aliases must not replace another configured command.";
      }
    ];
    home.packages = [ (lib.hiPrio cfg.package) ];
    home.activation.reconcileDarwinApplications =
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "copyApps" ]
        ''
          run ${lib.getExe cfg.package}
        '';
  };
}
