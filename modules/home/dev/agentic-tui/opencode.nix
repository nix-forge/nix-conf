{
  config,
  lib,
  myLib,
  pkgs,
  self,
  system,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  mkTool = command: extensions: { inherit command extensions; };

  ruffFixAndFormat = writeBashTemplate {
    name = "opencode-ruff-fix-and-format";
    src = ./scripts/opencode-ruff-fix-and-format.sh;
    replacements = {
      bash = lib.getExe pkgs.bash;
      ruff = lib.getExe pkgs.ruff;
    };
  };

  dprintAstroConfig = pkgs.writeText "opencode-dprint-astro.json" (
    builtins.toJSON { plugins = [ "${pkgs.dprint-plugins.g-plane-markup_fmt}/plugin.wasm" ]; }
  );

  documentedLsp = {
    # astro = mkTool [ (lib.getExe pkgs.astro-language-server) "--stdio" ] [ ".astro" ];
    bash =
      (mkTool [ (lib.getExe pkgs.bash-language-server) "start" ] [ ".sh" ".bash" ".zsh" ".ksh" ".envrc" ])
      // {
        env = {
          SHELLCHECK_PATH = "${lib.getExe pkgs.shellcheck}";
          SHELLCHECK_ARGUMENTS = "--severity=warning --enable=${
            builtins.concatStringsSep "," [
              "deprecate-which"
              "add-default-case"
              "check-set-e-suppressed"
              "check-extra-masked-returns"
              "check-unassigned-uppercase"
            ]
          }";
        };
      };
    clangd =
      mkTool
        [ (lib.getExe' pkgs.clang-tools "clangd") "--background-index" "--clang-tidy" ]
        [
          ".c"
          ".cpp"
          ".cc"
          ".cxx"
          ".c++"
          ".h"
          ".hpp"
          ".hh"
          ".hxx"
          ".h++"
        ];
    eslint = {
      disabled = true;
    };
    gopls = mkTool [ (lib.getExe pkgs.gopls) ] [ ".go" ];
    lua-ls = mkTool [ (lib.getExe pkgs.lua-language-server) ] [ ".lua" ];
    nixd = mkTool [ (lib.getExe pkgs.nixd) ] [ ".nix" ];
    oxlint =
      mkTool
        [ (lib.getExe pkgs.oxlint) "--lsp" ]
        [
          ".ts"
          ".tsx"
          ".js"
          ".jsx"
          ".mjs"
          ".cjs"
          ".mts"
          ".cts"
          ".vue"
          ".astro"
          ".svelte"
        ];
    pyright = {
      disabled = true;
    };
    ruff = mkTool [ (lib.getExe pkgs.ruff) "server" ] [ ".py" ".pyi" ".ipynb" ];
    rust = mkTool [ (lib.getExe pkgs.rust-analyzer) ] [ ".rs" ];
    tinymist = mkTool [ (lib.getExe pkgs.tinymist) "lsp" ] [ ".typ" ".typc" ];
    ty = mkTool [ (lib.getExe pkgs.ty) "server" ] [ ".py" ".pyi" ".ipynb" ];
    typescript =
      mkTool
        [ (lib.getExe pkgs.typescript-language-server) "--stdio" ]
        [
          ".ts"
          ".tsx"
          ".js"
          ".jsx"
          ".mjs"
          ".cjs"
          ".mts"
          ".cts"
        ];
    yaml-ls = mkTool [ (lib.getExe pkgs.yaml-language-server) "--stdio" ] [ ".yaml" ".yml" ];
  };

  documentedFormatters = {
    astro = mkTool [ (lib.getExe pkgs.dprint) "fmt" "--config" dprintAstroConfig "$FILE" ] [ ".astro" ];
    cargofmt = mkTool [ (lib.getExe pkgs.cargo) "fmt" "--" "$FILE" ] [ ".rs" ];
    clang-format =
      mkTool
        [ (lib.getExe' pkgs.clang-tools "clang-format") "-i" "$FILE" ]
        [ ".c" ".cpp" ".h" ".hpp" ".ino" ];
    gofmt = mkTool [ (lib.getExe' pkgs.go "gofmt") "-w" "$FILE" ] [ ".go" ];
    nixfmt = mkTool [ (lib.getExe pkgs.nixfmt) "$FILE" ] [ ".nix" ];
    oxfmt = mkTool [ (lib.getExe pkgs.oxfmt) "$FILE" ] [ ".js" ".jsx" ".ts" ".tsx" ] // {
      environment = {
        BUN_BE_BUN = "1";
      };
    };
    prettier = {
      disabled = true;
    };
    ruff = mkTool [ ruffFixAndFormat "$FILE" ] [ ".py" ".pyi" ".ipynb" ];
    shfmt =
      mkTool
        [
          (lib.getExe pkgs.shfmt)
          "-w"
          "-ln=bash"
          "-i=2"
          "-ci"
          "-bn"
          "-sr"
          "$FILE"
        ]
        [ ".sh" ".bash" ];
    typstyle = mkTool [ (lib.getExe pkgs.typstyle) "--inplace" "$FILE" ] [ ".typ" ];
    uv = {
      disabled = true;
    };
  };

  typstSkillSrc = fetchGit {
    url = "https://github.com/lucifer1004/claude-skill-typst.git";
    ref = "main";
    rev = "6628cbf7205fe5059209875f69d80c962064b360";
  };

  anthropicSkills = self.packages.${system}.anthropic-skills;
  openaiSkills = self.packages.${system}.openai-skills;
  mattpocockSkills = self.packages.${system}.mattpocock-skills;
  pstackSkills = self.packages.${system}.pstack-skills;
  supportsRemindctl = self.packages.${system} ? remindctl;
  remindctl = self.packages.${system}.remindctl;
  skillPath = package: name: "${package}/share/agent-skills/${name}";
  skillSet = package: names: lib.genAttrs names (name: skillPath package name);

  anthropicOpenCodeSkills = [
    "anthropic-brand-guidelines"
    "anthropic-frontend-design"
    "anthropic-internal-comms"
    "anthropic-mcp-builder"
    "anthropic-skill-creator"
    "anthropic-theme-factory"
    "anthropic-web-artifacts-builder"
    "anthropic-webapp-testing"
  ];
  openaiOpenCodeSkills = [
    "openai-cli-creator"
    "openai-gh-address-comments"
    "openai-gh-fix-ci"
    "openai-pdf"
    "openai-playwright"
    "openai-playwright-interactive"
    "openai-screenshot"
    "openai-security-best-practices"
    "openai-security-ownership-map"
    "openai-security-threat-model"
    "openai-yeet"
  ];
  mattpocockOpenCodeSkills = [
    "mattpocock-ask-matt"
    "mattpocock-codebase-design"
    "mattpocock-code-review"
    "mattpocock-diagnosing-bugs"
    "mattpocock-domain-modeling"
    "mattpocock-grill-me"
    "mattpocock-grill-with-docs"
    "mattpocock-grilling"
    "mattpocock-handoff"
    "mattpocock-research"
    "mattpocock-resolving-merge-conflicts"
    "mattpocock-setup-matt-pocock-skills"
    "mattpocock-tdd"
    "mattpocock-wizard"
    "mattpocock-writing-for-agents"
  ];
  pstackOpenCodeSkills = [ "pstack-unslop" ];

  opencodeNotifierDarwinFallback = writeBashTemplate {
    name = "opencode-notifier-darwin-fallback";
    src = ./scripts/opencode-notifier-darwin-fallback.sh;
    replacements.bash = lib.getExe pkgs.bash;
  };
in
{
  programs.opencode = {
    enable = true;
    skills = {
      typst = "${typstSkillSrc}/skills/typst";
    }
    // lib.optionalAttrs supportsRemindctl { apple-reminders = remindctl.agentSkill; }
    // skillSet anthropicSkills anthropicOpenCodeSkills
    // skillSet openaiSkills openaiOpenCodeSkills
    // skillSet mattpocockSkills mattpocockOpenCodeSkills
    // skillSet pstackSkills pstackOpenCodeSkills;
    settings = {
      # Nix manages updates via the pinned package; never let opencode self-update
      # and fight the store.
      autoupdate = false;
      # Lock the default so an upstream default change cannot start uploading
      # sessions. Use /share explicitly if sharing is ever needed.
      share = "manual";
      plugin = [
        "@opencode-ai/plugin@${pkgs.opencode.version}"
        "opencode-gemini-auth@1.4.15"
        "@mohak34/opencode-notifier@0.2.8"
      ];
      formatter = documentedFormatters;
      lsp = documentedLsp;
      permission = {
        # Danger-full-access equivalent: allow everything by default so normal
        # work never prompts (codex `--dangerously-bypass-approvals-and-sandbox`
        # analogue is `opencode --auto`, which auto-approves asks but still
        # respects explicit denies below).
        "*" = "allow";
        external_directory = "allow";
        doom_loop = "allow";

        read =
          let
            afterStar = lib.hm.dag.entryAfter [ "*" ];
          in
          {
            "*" = "allow";
            # Re-assert the upstream .env defaults: the global allow above
            # would otherwise permit secret files. Last match wins, so the
            # example exception must come after its deny.
            "*.env" = afterStar "deny";
            "*.env.*" = lib.hm.dag.entryAfter [ "*.env" ] "deny";
            "*.env.example" = lib.hm.dag.entryAfter [ "*.env.*" ] "allow";

            "${config.home.homeDirectory}/.ssh/**" = afterStar "deny";
            "${config.home.homeDirectory}/.gnupg/**" = afterStar "deny";
            "${config.xdg.dataHome}/opencode/auth.json" = afterStar "deny";
            "${config.xdg.dataHome}/opencode/mcp-auth.json" = afterStar "deny";
          };
      };
    };
  };

  xdg.configFile."opencode/opencode-notifier.json".text = builtins.toJSON (
    {
      notification = true;
      sound = true;
      suppressWhenFocused = true;
      showProjectName = true;
      showSessionTitle = true;

      events = {
        permission = {
          sound = true;
          notification = true;
          command = true;
        };
        question = {
          sound = true;
          notification = true;
          command = true;
        };
        plan_exit = {
          sound = true;
          notification = true;
          command = true;
        };
        complete = {
          sound = true;
          notification = true;
          command = true;
        };
        error = {
          sound = true;
          notification = true;
          command = true;
        };
        subagent_complete = {
          sound = false;
          notification = false;
          command = true;
        };
        user_cancelled = {
          sound = false;
          notification = false;
          command = true;
        };
      };

      messages = {
        permission = "Approval needed: {sessionTitle}";
        question = "Question for you: {sessionTitle}";
        plan_exit = "Plan ready for build approval: {sessionTitle}";
      };
    }
    // lib.optionalAttrs isDarwin {
      notificationSystem = "ghostty";
      command = {
        enabled = true;
        path = opencodeNotifierDarwinFallback;
        args = [
          "{event}"
          "{message}"
        ];
      };
    }
    // lib.optionalAttrs isLinux { linux.grouping = true; }
  );

  home.packages =
    lib.optional supportsRemindctl remindctl ++ lib.optionals isLinux [ pkgs.libnotify ];

  home.sessionVariables = {
    # LSP code intelligence (docs use the singular TOOL name; the old plural
    # TOOLS key was a no-op).
    OPENCODE_EXPERIMENTAL_LSP_TOOL = "true";
    OPENCODE_EXPERIMENTAL_LSP_TY = "true";
    # We ship every LSP/formatter from Nix, so never auto-download binaries.
    OPENCODE_DISABLE_LSP_DOWNLOAD = "true";

    OPENCODE_EXPERIMENTAL_OXFMT = "true";

    OPENCODE_ENABLE_EXA = "true";
    OPENCODE_EXPERIMENTAL_EXA = "true";

    OPENCODE_EXPERIMENTAL_PLAN_MODE = "true";
  };
}
