{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-skills;
  stableMattSkills = [
    "ask-matt"
    "code-review"
    "codebase-design"
    "diagnosing-bugs"
    "domain-modeling"
    "grill-me"
    "grill-with-docs"
    "grilling"
    "handoff"
    "implement"
    "implement-spec"
    "improve-codebase-architecture"
    "pr"
    "prototype"
    "research"
    "retro"
    "setup-matt-pocock-skills"
    "tdd"
    "teach"
    "to-questionnaire"
    "to-spec"
    "to-tickets"
    "triage"
    "wait-what"
    "wayfinder"
    "wizard"
    "writing-for-agents"
  ];
  # Task-specific workflows with their interview dependencies. Global execution
  # controllers, tracker automation and one-time setup remain explicit opt-ins.
  defaultMattSkills = [
    "code-review"
    "codebase-design"
    "diagnosing-bugs"
    "domain-modeling"
    "grill-me"
    "grill-with-docs"
    "grilling"
    "handoff"
    "pr"
    "research"
    "tdd"
    "writing-for-agents"
  ];
  mattSkills = lib.genAttrs (map (name: "mattpocock-${name}") cfg.mattpocock.skills) (
    name: "${cfg.mattpocock.package}/share/agent-skills/${name}"
  );
  selectedSkills = lib.optionalAttrs cfg.mattpocock.enable mattSkills // cfg.extraSkills;
  superpowers = cfg.superpowers.source;
  superpowersSkills = [
    "brainstorming"
    "diagnosing-superpowers"
    "dispatching-parallel-agents"
    "executing-plans"
    "finishing-a-development-branch"
    "receiving-code-review"
    "requesting-code-review"
    "subagent-driven-development"
    "systematic-debugging"
    "test-driven-development"
    "using-git-worktrees"
    "using-superpowers"
    "verification-before-completion"
    "writing-plans"
    "writing-skills"
  ];
  directorySkills =
    selectedSkills
    // lib.optionalAttrs cfg.superpowers.enable (
      lib.genAttrs superpowersSkills (name: "${superpowers}/skills/${name}")
    );
in
{
  options.programs.agent-skills = {
    enable = lib.mkEnableOption "shared declarative agent skill catalogs" // {
      default = true;
    };
    mattpocock = {
      enable = lib.mkEnableOption "Matt Pocock skills" // {
        default = true;
      };
      package = lib.mkPackageOption pkgs "mattpocock-skills" { };
      skills = lib.mkOption {
        type = with lib.types; listOf (enum stableMattSkills);
        default = defaultMattSkills;
        description = "Stable upstream skills to install, with the mattpocock- namespace. Defaults to complementary design, interview, testing, review and documentation workflows; global controllers and specialist workflows require explicit selection.";
      };
    };
    superpowers = {
      # This is a complete workflow controller, including startup hooks on
      # Claude/OpenCode, rather than a collection of independent references.
      enable = lib.mkEnableOption "the complete, opt-in Superpowers workflow";
      source = lib.mkOption {
        type = lib.types.package;
        default =
          (pkgs.fetchFromGitHub {
            name = "superpowers";
            owner = "obra";
            repo = "superpowers";
            rev = "22f0b463e7a5e579904dd6211a520321035526f7";
            hash = "sha256-rP5YsyGuPd9YSW/Fj3aukrq1bLuV+nwwQMK4JaZQgkI=";
          })
          // {
            version = "7.0.2";
          };
        description = "Pinned complete Superpowers repository, including native manifests, hooks, agents and OpenCode entrypoint. Update version, revision and hash together.";
      };
    };
    extraSkills = lib.mkOption {
      type = with lib.types; attrsOf path;
      default = { };
      description = "Additional complete skill directories shared by the selected clients. Names must not collide with either catalog.";
    };
    clients = {
      codex.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.programs.codex.enable;
        description = "Integrate Codex CLI and desktop; T3 Codex sessions inherit this state directory.";
      };
      claude-code.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.programs.claude-code.enable;
        description = "Integrate Claude Code, including T3 Claude sessions.";
      };
      opencode.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.programs.opencode.enable;
        description = "Integrate OpenCode with its native skill and plugin options.";
      };
      copilot.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose personal skills for GitHub Copilot in VS Code and CLI, without plugin startup hooks.";
      };
      cursor.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose skill directories to Cursor editor and CLI. This does not install Cursor plugin hooks.";
      };
    };
  };
  config = lib.mkMerge [
    {
      # Native mutable settings preserve absent keys. Explicitly retire this
      # feature's own enable flag when either the catalog or client is disabled.
      programs.codex.settings.plugins."superpowers@home-manager".enabled =
        cfg.enable && cfg.superpowers.enable && cfg.clients.codex.enable;
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion =
            !cfg.mattpocock.enable
            ||
              builtins.all
                (
                  skill:
                  !(builtins.elem skill cfg.mattpocock.skills) || builtins.elem "grilling" cfg.mattpocock.skills
                )
                [
                  "grill-me"
                  "grill-with-docs"
                ];
          message = "Matt interview wrappers require grilling in programs.agent-skills.mattpocock.skills.";
        }
        {
          assertion =
            !cfg.mattpocock.enable
            || !(builtins.elem "grill-with-docs" cfg.mattpocock.skills)
            || builtins.elem "domain-modeling" cfg.mattpocock.skills;
          message = "grill-with-docs requires domain-modeling in programs.agent-skills.mattpocock.skills.";
        }

        {
          assertion = builtins.all (name: builtins.match "[a-z0-9]+(-[a-z0-9]+)*" name != null) (
            builtins.attrNames cfg.extraSkills
          );
          message = "programs.agent-skills.extraSkills names must use lowercase kebab-case.";
        }
        {
          assertion = builtins.all (
            name: !(builtins.hasAttr name mattSkills) && !(builtins.elem name superpowersSkills)
          ) (builtins.attrNames cfg.extraSkills);
          message = "programs.agent-skills.extraSkills must not shadow managed catalog names.";
        }
        {
          assertion =
            !cfg.clients.opencode.enable
            || !cfg.superpowers.enable
            || (
              config.programs.opencode.package != null
              && lib.versionAtLeast (lib.getVersion config.programs.opencode.package) "2.0.4"
            );
          message = "The native Superpowers OpenCode plugin requires a Home Manager OpenCode package at version 2.0.4 or later.";
        }
      ];
      programs = {
        codex = lib.mkIf cfg.clients.codex.enable {
          skills = selectedSkills;
          plugins = lib.optional cfg.superpowers.enable superpowers;
        };
        claude-code = lib.mkIf cfg.clients.claude-code.enable {
          skills = selectedSkills;
          plugins = lib.optionalAttrs cfg.superpowers.enable { inherit superpowers; };
        };
        opencode = lib.mkIf cfg.clients.opencode.enable {
          skills = selectedSkills;
          # The v2 plugin registers its own skills and startup guidance. Installing
          # loose Superpowers skills as well would duplicate discovery.
          settings.plugins = lib.optional cfg.superpowers.enable (toString superpowers);
        };
      };
      home.file = lib.mkMerge [
        (lib.mkIf cfg.clients.cursor.enable (
          lib.mapAttrs' (
            name: source: lib.nameValuePair ".cursor/skills/${name}" { inherit source; }
          ) directorySkills
        ))
        (lib.mkIf cfg.clients.copilot.enable (
          lib.mapAttrs' (
            name: source: lib.nameValuePair ".copilot/skills/${name}" { inherit source; }
          ) directorySkills
        ))
      ];
    })
  ];
}
