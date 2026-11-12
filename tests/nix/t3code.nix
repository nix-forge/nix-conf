{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  # A package with the official provider-wrapper override contract. Its output
  # makes the wrapper choice observable without launching a real server.
  backend = lib.makeOverridable (
    {
      enableCodex ? true,
      enableClaude ? false,
      enableOpencode ? false,
    }:
    pkgs.writeShellScriptBin "t3" ''
      printf '%s\0' ${
        lib.escapeShellArgs (
          map lib.boolToString [
            enableCodex
            enableClaude
            enableOpencode
          ]
        )
      } \
        "''${CODEX_HOME:-unset}" "''${XDG_CONFIG_HOME:-unset}" "''${XDG_DATA_HOME:-unset}" \
        "''${XDG_STATE_HOME:-unset}" "''${XDG_CACHE_HOME:-unset}" "''${CLAUDE_CONFIG_DIR:-unset}" \
        "''${OPENCODE_CONFIG:-unset}" "$(command -v fixture-extra)" "$@"
    ''
  ) { };
  gui =
    name:
    pkgs.symlinkJoin {
      inherit name;
      paths = [ backend ];
      passthru.serverPackage = backend;
      meta.mainProgram = "t3";
    };
  codex = pkgs.writeShellScriptBin "codex" "exit 0";
  claude = (pkgs.writeShellScriptBin "claude" "exit 0").overrideAttrs { version = "2.1.100"; };
  opencode = pkgs.writeShellScriptBin "opencode" "exit 0";
  extraTool = pkgs.writeShellScriptBin "fixture-extra" "exit 0";
  homeFor =
    package: extra:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs.extend (_: _: { t3code = package; });
      extraSpecialArgs = { inherit myLib; };
      modules = [
        ../../modules/home/dev/agentic-gui/t3-code.nix
        ../../modules/home/dev/agentic-gui/codex/settings.nix
        ({ config, ... }: {
          home.username = "t3-check";
          home.homeDirectory =
            if pkgs.stdenv.hostPlatform.isDarwin then "/Users/t3-check" else "/home/t3-check";
          home.stateVersion = "26.05";
          home.preferXdgDirectories = true;
          programs.codex = {
            enable = true;
            package = codex;
          };
          programs.claude-code = {
            enable = true;
            package = claude;
            configDir = "${config.home.homeDirectory}/custom-claude";
            plugins.fixture = ./fixtures/t3code-plugin;
          };
          programs.opencode = {
            enable = true;
            package = opencode;
            extraPackages = [ extraTool ];
            mutableSettings = true;
            settings.update = "disable";
          };
        })
        extra
      ];
    }).config;
  first = homeFor (gui "first-gui") { };
  second = homeFor (gui "second-gui") { };
  disabled = homeFor (gui "disabled-gui") { programs.t3code.server.enable = false; };
  codexSettings = first.programs.t3code.userSettings.providerInstances.codex;
  service = first.systemd.user.services.t3code;
  darwinService = first.launchd.agents.t3code.config;
  expectedHome = "${first.xdg.configHome}/codex";
  merger = pkgs.writeShellScript "t3code-fixture-merge" first.home.activation.t3codeSettingsActivation.data;
  existingSettings = pkgs.writeText "t3code-existing-settings.json" (
    builtins.toJSON {
      providerInstances = {
        codex = {
          driver = "codex";
          enabled = false;
          config = {
            homePath = "old-home";
            customModels = [ "retained-model" ];
            shadowHomePath = "retained-shadow";
          };
        };
        second = {
          driver = "codex";
          enabled = false;
        };
      };
    }
  );
  command =
    if pkgs.stdenv.hostPlatform.isLinux then
      service.Service.ExecStart
    else
      lib.escapeShellArgs darwinService.ProgramArguments;
  environment =
    if pkgs.stdenv.hostPlatform.isLinux then
      service.Service.Environment
    else
      lib.mapAttrsToList (name: value: "${name}=${value}") darwinService.EnvironmentVariables;
in
assert first.programs.t3code.mutableUserSettings;
assert codexSettings.driver == "codex";
assert codexSettings.config.binaryPath == lib.getExe codex;
assert codexSettings.config.homePath == expectedHome;
assert
  first.programs.t3code.userSettings.providerInstances.claudeAgent.config.binaryPath
  == lib.getExe first.programs.claude-code.finalPackage;
assert first.programs.claude-code.finalPackage != claude;
assert !(codexSettings ? enabled);
assert !(codexSettings.config ? customModels);
assert !(disabled.systemd.user.services ? t3code);
assert !(disabled.launchd.agents ? t3code);
assert
  if pkgs.stdenv.hostPlatform.isLinux then
    service.Unit.X-SwitchMethod == "keep-old"
    && service.Service.ExecStart == second.systemd.user.services.t3code.Service.ExecStart
    && service.Service.RestartPreventExitStatus == [ 78 ]
    && service.Service.TimeoutStopSec == 90
  else
    darwinService.ProgramArguments == second.launchd.agents.t3code.config.ProgramArguments
    && darwinService.ExitTimeOut == 90
    && darwinService.Label == "com.t3tools.t3code.service";
pkgs.runCommand "t3code-harness-integration" { nativeBuildInputs = [ pkgs.jq ]; } ''
  mapfile -d $'\0' -t observed < <(env ${lib.escapeShellArgs environment} ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg command})
  test "''${observed[0]}" = false
  test "''${observed[1]}" = false
  test "''${observed[2]}" = false
  test "''${observed[3]}" = ${lib.escapeShellArg expectedHome}
  test "''${observed[4]}" = ${lib.escapeShellArg first.xdg.configHome}
  test "''${observed[5]}" = ${lib.escapeShellArg first.xdg.dataHome}
  test "''${observed[6]}" = ${lib.escapeShellArg first.xdg.stateHome}
  test "''${observed[7]}" = ${lib.escapeShellArg first.xdg.cacheHome}
  test "''${observed[8]}" = ${lib.escapeShellArg first.programs.claude-code.configDir}
  test "''${observed[9]}" = ${lib.escapeShellArg first.home.sessionVariables.OPENCODE_CONFIG}
  test "''${observed[10]}" = ${lib.getExe extraTool}
  expected=(serve --host 127.0.0.1 --port 3773 --base-dir ${lib.escapeShellArg "${first.home.homeDirectory}/.t3"})
  for index in "''${!expected[@]}"; do
    test "''${observed[index + 11]}" = "''${expected[index]}"
  done

  # Relocate the real activation script into private sandbox state.
  settings="$TMPDIR/fixture-home/.t3/userdata/settings.json"
  mkdir -p "$(dirname "$settings")"
  cp ${existingSettings} "$settings"
  chmod 600 "$settings"
  substitute ${merger} merger.sh --replace-fail \
    ${lib.escapeShellArg "${first.home.homeDirectory}/.t3/userdata/settings.json"} "$settings"
  ${pkgs.bash}/bin/bash merger.sh
  jq -e --arg home ${lib.escapeShellArg expectedHome} --arg binary ${lib.escapeShellArg (lib.getExe codex)} \
    '.providerInstances.codex | .enabled == false and .config.homePath == $home and .config.binaryPath == $binary and .config.customModels == ["retained-model"] and .config.shadowHomePath == "retained-shadow"' "$settings"
  jq -e '.providerInstances.second.enabled == false' "$settings"
  test "$(stat -c %a "$settings")" = 600
  touch "$out"
''
