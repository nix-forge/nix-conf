{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cfg = config.macos.applications;
  appsDirectory = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  render = myLib.templates.renderText;
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
    writeShellApplication {
      inherit name;
      text =
        render
          {
            name = "launch-managed-app.sh.in";
            text = ''
              # shellcheck shell=bash
              app=@app@
              executable=@executable@

              if [[ ! -d "$app/Contents" ]]; then
                printf 'Managed application is missing; activate Home Manager first: %s\n' "$app" >&2
                exit 1
              fi

              if [[ -n $executable ]]; then
                if [[ ! -x "$app/$executable" ]]; then
                  printf 'Managed application CLI is missing: %s/%s\n' "$app" "$executable" >&2
                  exit 1
                fi
                exec "$app/$executable" "$@"
              fi

              exec @open@ -a "$app" --args "$@"
            '';
          }
          {
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
      (writeShellApplication {
        name = "hm-macos-applications";
        text =
          render
            {
              name = "reconcile-applications.sh.in";
              text = ''
                # shellcheck shell=bash
                @lifecycleCheck@
                exec @helper@ @args@ "$@"
              '';
            }
            {
              lifecycleCheck = lib.optionalString (cfg.manageAll || cfg.protectedBundles != [ ]) ''
                if [[ " ''${*} " == *" --check "* ]]; then
                  ${lib.getExe cfg.lifecyclePackage} --mode check || exit "$?"
                fi
              '';
              helper = lib.getExe' manager "hm-macos-applications-helper";
              args = managerArgs;
            };
      })
    ];
    postBuild = lib.concatMapStringsSep "\n" (
      item:
      render
        {
          name = "link-command-alias.sh.in";
          text = ''
            # shellcheck shell=bash
            command_name=@name@
            alias_name=@alias@
            : "''${out:?Nix must provide the output directory}"
            # Case-insensitive stores already resolve case-only aliases to the original.
            if [[ ! -e "$out/bin/$alias_name" ]]; then
              ln -s "$command_name" "$out/bin/$alias_name"
            fi
          '';
        }
        {
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
