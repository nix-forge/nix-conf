{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  skillPkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    overlays = [ inputs.nixpkgs-personal.overlays.default ];
    config.allowUnfreePredicate =
      package:
      lib.elem (lib.getName package) [
        "openai-skills"
        "anthropic-skills"
      ];
  };
  homeFor =
    extra:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = skillPkgs;
      extraSpecialArgs = {
        inherit myLib;
        system = pkgs.stdenv.hostPlatform.system;
        self.packages.${pkgs.stdenv.hostPlatform.system} = { };
      };
      modules = [
        ../../modules/home/dev/agentic-tui/agent-skills.nix
        {
          home.username = "skill-check";
          home.homeDirectory =
            if pkgs.stdenv.hostPlatform.isDarwin then "/Users/skill-check" else "/home/skill-check";
          home.stateVersion = "26.05";
          programs.codex.enable = true;
          programs.claude-code.enable = true;
          programs.opencode.enable = true;
        }
        extra
      ];
    }).config;
  core = homeFor { };
  optional = homeFor {
    programs.agent-skills.clients = {
      codex.bundles = [
        "frontend"
        "documents"
        "authoring"
      ];
      claude.bundles = [ ];
      opencode = {
        bundles = [
          "github"
          "browser"
          "security"
        ];
        extraSkills.fixture = ./fixtures/agent-skill;
      };
    };
  };
  collision = homeFor {
    programs.agent-skills.clients.codex.extraSkills.pstack-unslop = ./fixtures/agent-skill;
  };
  invalid = homeFor { programs.agent-skills.clients.codex.bundles = [ "not-a-bundle" ]; };
  disabled = homeFor {
    programs.codex.enable = lib.mkForce false;
    programs.claude-code.enable = lib.mkForce false;
    programs.opencode.enable = lib.mkForce false;
  };
  mixed = homeFor {
    programs.agent-skills.clients.claude.bundles = [
      "core"
      "frontend"
    ];
    programs.agent-skills.clients.opencode.bundles = [ ];
  };
  configured = homeFor { imports = [ ../../modules/home/dev/agentic-tui/opencode.nix ]; };
  denied =
    home: name:
    builtins.any (
      rule: rule.action == "skill" && rule.resource == name && rule.effect == "deny"
    ) home.programs.opencode.settings.permissions;
  names = program: builtins.attrNames program.skills;
  programs = [
    core.programs.codex
    core.programs.claude-code
    core.programs.opencode
  ];
  # Build the real client-generated links, not only the catalog attrsets.
  outputs = lib.imap0 (
    index: _program:
    let
      expected = "${
        if index == 0 then
          ".codex"
        else if index == 1 then
          ".claude"
        else
          ".config/opencode"
      }/skills/";
      target = file: lib.removePrefix "${core.home.homeDirectory}/" file.target;
      files = lib.filterAttrs (_: file: lib.hasPrefix expected (target file)) core.home.file;
    in
    {
      name = "client-${toString index}";
      path = pkgs.linkFarm "agent-skills-client-${toString index}" (
        lib.mapAttrsToList (_: file: {
          name = lib.removePrefix expected (target file);
          path = file.source;
        }) files
      );
    }
  ) programs;
  generated = pkgs.linkFarm "agent-skills-clients" outputs;
in
assert names core.programs.codex == names core.programs.claude-code;
assert names core.programs.codex == names core.programs.opencode;
assert builtins.length (names core.programs.codex) == 16;
assert names optional.programs.claude-code == [ ];
assert
  names optional.programs.codex == [
    "anthropic-frontend-design"
    "anthropic-mcp-builder"
  ];
assert optional.programs.opencode.skills ? fixture;
assert optional.programs.opencode.skills ? openai-gh-fix-ci;
assert !(optional.programs.opencode.skills ? pstack-unslop);
assert denied optional "pstack-unslop";
assert !(denied optional "openai-gh-fix-ci");
assert mixed.programs.claude-code.skills ? anthropic-frontend-design;
assert denied mixed "anthropic-frontend-design";
assert denied mixed "mattpocock-tdd";
assert !(builtins.tryEval (builtins.deepSeq collision.programs.codex.skills true)).success;
assert !(builtins.tryEval (builtins.deepSeq invalid.programs.codex.skills true)).success;
assert builtins.all (program: program.skills == { }) [
  disabled.programs.codex
  disabled.programs.claude-code
  disabled.programs.opencode
];
pkgs.runCommand "agent-skills-integration"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.check-jsonschema
    ];
  }
  ''
    check-jsonschema --schemafile ${skillPkgs.opencode.jsonschema.config} \
      ${configured.xdg.configFile."opencode/opencode.json".source}
    jq -e '[.permissions[] | select(.action == "skill" and .effect == "deny") | .resource] | index("anthropic-frontend-design") != null and index("mattpocock-tdd") != null' \
      ${mixed.xdg.configFile."opencode/opencode.json".source} > /dev/null
    grep -q 'allow_implicit_invocation: false' ${generated}/client-0/pstack-unslop/agents/openai.yaml
    for client in ${generated}/client-*; do
      test -f "$client/mattpocock-tdd/tests.md"
      test -f "$client/mattpocock-writing-for-agents/SKILL-MECHANICS.md"
      test -f "$client/mattpocock-ask-matt/agents/openai.yaml"
      grep -q 'allow_implicit_invocation: false' "$client/mattpocock-ask-matt/agents/openai.yaml"
      grep -q 'disable-model-invocation: true' "$client/pstack-unslop/SKILL.md"
      test "$(find -L "$client" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)" -eq 16
    done
    touch "$out"
  ''
