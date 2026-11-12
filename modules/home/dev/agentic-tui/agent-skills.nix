{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-skills;
  skillSet = package: names: lib.genAttrs names (name: "${package}/share/agent-skills/${name}");
  bundles = {
    core =
      skillSet pkgs.mattpocock-skills [
        "mattpocock-ask-matt"
        "mattpocock-codebase-design"
        "mattpocock-code-review"
        "mattpocock-diagnosing-bugs"
        "mattpocock-domain-modeling"
        "mattpocock-grill-me"
        "mattpocock-grill-with-docs"
        "mattpocock-grilling"
        "mattpocock-handoff"
        "mattpocock-pr"
        "mattpocock-research"
        "mattpocock-setup-matt-pocock-skills"
        "mattpocock-tdd"
        "mattpocock-wizard"
        "mattpocock-writing-for-agents"
      ]
      // skillSet pkgs.pstack-skills [ "pstack-unslop" ];
    frontend = skillSet pkgs.anthropic-skills [ "anthropic-frontend-design" ];
    github = skillSet pkgs.openai-skills [
      "openai-gh-address-comments"
      "openai-gh-fix-ci"
    ];
    browser = skillSet pkgs.openai-skills [
      "openai-playwright"
      "openai-screenshot"
    ];
    documents = skillSet pkgs.openai-skills [ "openai-pdf" ];
    security = skillSet pkgs.openai-skills [
      "openai-security-best-practices"
      "openai-security-ownership-map"
      "openai-security-threat-model"
    ];
    authoring = skillSet pkgs.anthropic-skills [
      "anthropic-mcp-builder"
      "anthropic-skill-creator"
    ];
  };
  # Codex already supplies these workflows through its native skills/plugins.
  nativeCodexSkills = [
    "anthropic-skill-creator"
    "openai-pdf"
    "openai-playwright"
    "openai-screenshot"
  ];
  # Claude's frontmatter alone is not Codex's native invocation policy.
  explicitUnslop = pkgs.runCommand "pstack-unslop-codex" { } ''
    cp -R ${pkgs.pstack-skills}/share/agent-skills/pstack-unslop "$out"
    chmod -R u+w "$out"
    mkdir -p "$out/agents"
    cp ${./pstack-unslop-openai.yaml} "$out/agents/openai.yaml"
  '';
  clientModule = lib.types.submodule {
    options = {
      bundles = lib.mkOption {
        type = lib.types.listOf (lib.types.enum (builtins.attrNames bundles));
        default = [ "core" ];
        description = "Selected capability bundles. An empty list disables catalog skills for this client.";
      };
      extraSkills = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.path
            lib.types.str
            lib.types.package
          ]
        );
        default = { };
        description = "Additional complete skill directories. Catalog names cannot be replaced here.";
      };
    };
  };
  selected =
    client: lib.foldl' (result: bundle: result // bundles.${bundle}) { } cfg.clients.${client}.bundles;
  skillsFor =
    client:
    (
      if client == "codex" then
        removeAttrs (selected client) nativeCodexSkills
        // lib.optionalAttrs (selected client ? pstack-unslop) { pstack-unslop = "${explicitUnslop}"; }
      else
        selected client
    )
    // cfg.clients.${client}.extraSkills;
  clientPrograms = {
    codex = "codex";
    claude = "claude-code";
    opencode = "opencode";
  };
  catalogNames = lib.unique (lib.concatMap builtins.attrNames (builtins.attrValues bundles));
in
{
  options.programs.agent-skills.clients = lib.genAttrs (builtins.attrNames clientPrograms) (
    _:
    lib.mkOption {
      type = clientModule;
      default = { };
      description = "Portable skill selection for this harness.";
    }
  );

  config = lib.mkMerge (
    lib.mapAttrsToList (
      client: program:
      lib.mkIf config.programs.${program}.enable {
        assertions = [
          {
            assertion =
              lib.intersectLists (builtins.attrNames (selected client)) (
                builtins.attrNames cfg.clients.${client}.extraSkills
              ) == [ ];
            message = "programs.agent-skills.clients.${client}.extraSkills must not replace selected catalog skills.";
          }
        ];
        programs.${program} = {
          skills = skillsFor client;
          context = lib.mkBefore (builtins.readFile ./agent-skills-guidance.md);
        }
        // lib.optionalAttrs (client == "opencode") {
          # OpenCode also discovers ~/.claude/skills. Deny omitted catalog
          # entries so another client's bundle cannot bypass this selection.
          settings.permissions = lib.mkAfter (
            map (name: {
              action = "skill";
              resource = name;
              effect = "deny";
            }) (lib.subtractLists (builtins.attrNames (skillsFor client)) catalogNames)
          );
        };
      }
    ) clientPrograms
  );
}
