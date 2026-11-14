{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  reaPkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    overlays = [ inputs.nixpkgs-personal.overlays.default ];
  };
  inherit (reaPkgs) rea;
  homeFor =
    enabled:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = reaPkgs;
      extraSpecialArgs = { inherit myLib; };
      modules = [
        ../../modules/home/dev/agentic-tui/rea.nix
        ../../modules/home/dev/agentic-gui/codex/rea.nix
        {
          home = {
            username = "rea-check";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/rea-check" else "/home/rea-check";
            stateVersion = "26.05";
            preferXdgDirectories = true;
          };
          programs = {
            codex = {
              enable = enabled;
              package = null;
            };
            claude-code = {
              enable = enabled;
              package = null;
              configDir = ".custom-claude";
            };
            opencode = {
              enable = enabled;
              package = null;
            };
            # REA must not disable unrelated shared MCP integrations.
            mcp.servers.fixture.command = "fixture-mcp";
          };
        }
      ];
    }).config;
  enabled = homeFor true;
  disabled = homeFor false;
  skillFiles =
    home:
    lib.filterAttrs (
      _: file: lib.hasSuffix "/skills/reverse-engineer-anything" file.target
    ) home.home.file;
  generated = pkgs.linkFarm "rea-client-skills" (
    lib.imap0 (index: file: {
      name = "client-${toString index}";
      path = file.source;
    }) (builtins.attrValues (skillFiles enabled))
  );
  runtime = (import ../../modules/shared/codex-runtime.nix).nixos {
    inherit lib;
    pkgs = reaPkgs;
  };
  managed = runtime.environment.etc."codex/managed_config.toml".source;
  desktopSettings = pkgs.writeText "rea-codex-settings.json" (
    builtins.toJSON enabled.programs.chatgpt.settings
  );
in
assert builtins.length (builtins.attrNames (skillFiles enabled)) == 3;
assert skillFiles disabled == { };
assert builtins.elem rea enabled.home.packages;
assert !(enabled.programs.mcp.servers ? rea);
assert !enabled.programs.codex.enableMcpIntegration;
assert enabled.programs.claude-code.enableMcpIntegration;
assert enabled.programs.opencode.enableMcpIntegration;
pkgs.runCommand "rea-harness-integration"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.yq-go
    ];
  }
  ''
    for client in ${generated}/client-*; do
      diff -r ${rea.skills}/share/agent-skills/reverse-engineer-anything/references "$client/references"
      grep -q '^name: reverse-engineer-anything$' "$client/SKILL.md"
      grep -q 'rea-agents@${rea.version}' "$client/SKILL.md"
      grep -q 'requested follow-up depends on it' "$client/SKILL.md"
      grep -q 'active harness.*native browser controls' "$client/SKILL.md"
      grep -q 'workstation-job' "$client/SKILL.md"
    done
    jq -e '.mcp_servers.rea | .enabled == false and .args == ["mcp"] and .command == "${lib.getExe rea}"' ${desktopSettings} > /dev/null
    yq -p toml -o json ${managed} | jq -e '.mcp_servers.rea | .enabled == false and .args == ["mcp"] and .command == "${lib.getExe rea}"' > /dev/null
    jq -e '.mcp.fixture.command == ["fixture-mcp"] and (.mcp | has("rea") | not)' \
      ${enabled.xdg.configFile."opencode/opencode.json".source} > /dev/null
    # Reuse the package owner's real CLI/MCP/PTY checks in an isolated home.
    ${rea.nodejs}/bin/node ${inputs.nixpkgs-personal}/pkgs/by-name/re/rea/scripts/check-install.mts \
      ${rea} ${rea.skills} ${lib.escapeShellArg rea.version} ${lib.getExe pkgs.bash} --sandbox
    touch "$out"
  ''
