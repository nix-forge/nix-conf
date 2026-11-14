{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  prefix = "/build/activation-conflicts-fixture";
  configHome = "${prefix}/custom 'quoted' %literal$dollar config";
  selected = [
    "hypr/hyprland.lua"
    "codex/skills/reverse-engineer-anything"
    "opencode/opencode.json"
    "systemd/user/app-codex.slice"
    "systemd/user/codex-pressure.service"
    "Code/User/settings.json"
    "VSCodium/User/settings.json"
    "Code/User/profiles/Work 'quoted' %literal$dollar/settings.json"
  ];
  untouched = [
    "Disabled/User/settings.json"
    "Code/User/keybindings.json"
    "Unmanaged/User/settings.json"
  ];
  managed = "Code - Insiders/User/settings.json";
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit myLib;
      osConfig = {
        systemd.user.slices.background-workload.sliceConfig = {
          MemoryHigh = "1G";
          MemoryMax = "2G";
          MemorySwapMax = "0";
        };
        home-manager.backupCommand = "fixture-backup";
      };
    };
    modules = [
      ../../homes/desktop/local/memory.nix
      {
        home = {
          username = "tester";
          homeDirectory = prefix;
          stateVersion = "26.05";
          preferXdgDirectories = true;
          # Exercise platform-independent activation without the Linux runner.
          packages = lib.mkForce [ ];
        };
        programs.codex = {
          enable = true;
          package = null;
          skills.reverse-engineer-anything = pkgs.runCommand "fixture-codex-skill" { } ''
            mkdir -p "$out"
            printf '%s\n' '# Fixture skill' > "$out/SKILL.md"
          '';
        };
        xdg.configHome = configHome;
        xdg.configFile =
          lib.genAttrs
            (
              (lib.remove "codex/skills/reverse-engineer-anything" selected)
              ++ [
                managed
                "Code/User/keybindings.json"
              ]
            )
            (_: {
              text = "fixture";
            })
          // {
            "Disabled/User/settings.json" = {
              enable = false;
              text = "disabled";
            };
          };
        # Selection follows the managed identity; execution uses its actual target.
        home.file."${configHome}/VSCodium/User/settings.json".target =
          lib.mkForce "relocated/preferences.json";
      }
    ];
  };
  paths = names: map (name: "${configHome}/${name}") names;
in
pkgs.runCommand "activation-conflicts"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.python3
    ];
    FIXTURE_PREFIX = prefix;
    activation = pkgs.writeText "preserve-configuration-conflicts.sh" home.config.home.activation.preserveConfigurationConflicts.data;
    manifest = pkgs.writeText "activation-conflicts.json" (
      builtins.toJSON {
        selected = paths (lib.remove "VSCodium/User/settings.json" selected) ++ [
          "${prefix}/relocated/preferences.json"
        ];
        untouched = paths untouched;
        managed = "${configHome}/${managed}";
        managedLink = "${builtins.storeDir}/fixture-home-manager-files/config";
        foreignLink = "${builtins.storeDir}/foreign-fixture";
      }
    );
    fixtureBash = ./scripts/activation-conflicts-fixture.sh;
    driver = ./scripts/check_activation_conflicts.py;
    BASH_PROGRAM = lib.getExe pkgs.bash;
  }
  ''
    python3 "$driver"
    mkdir -p "$out"
  ''
