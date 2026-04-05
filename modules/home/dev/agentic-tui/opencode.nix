{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  mkTool = command: extensions: { inherit command extensions; };

  ruffFixAndFormat = pkgs.writeShellScript "opencode-ruff-fix-and-format" ''
    set -eu

    file="$1"

    ${lib.getExe pkgs.ruff} check --fix --exit-zero "$file"
    ${lib.getExe pkgs.ruff} format "$file"
  '';

  documentedLsp = {
    bash =
      mkTool
        [ (lib.getExe pkgs.bash-language-server) "start" ]
        [ ".sh" ".bash" ".zsh" ".ksh" ".envrc" ];
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
    deno = mkTool [ (lib.getExe pkgs.deno) "lsp" ] [ ".ts" ".tsx" ".js" ".jsx" ".mjs" ];
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
    ruff = (mkTool [ (lib.getExe pkgs.ruff) "server" ] [ ".py" ".pyi" ".ipynb" ]);
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
    cargofmt = mkTool [ (lib.getExe pkgs.cargo) "fmt" "--" "$FILE" ] [ ".rs" ];
    clang-format =
      mkTool
        [ (lib.getExe' pkgs.clang-tools "clang-format") "-i" "$FILE" ]
        [ ".c" ".cpp" ".h" ".hpp" ".ino" ];
    gofmt = mkTool [ (lib.getExe' pkgs.go "gofmt") "-w" "$FILE" ] [ ".go" ];
    nixfmt = mkTool [ (lib.getExe pkgs.nixfmt) "$FILE" ] [ ".nix" ];
    oxfmt = (mkTool [ (lib.getExe pkgs.oxfmt) "$FILE" ] [ ".js" ".jsx" ".ts" ".tsx" ]) // {
      disabled = true;
      environment = {
        BUN_BE_BUN = "1";
      };
    };
    prettier = {
      disabled = true;
    };
    ruff = mkTool [ ruffFixAndFormat "$FILE" ] [ ".py" ".pyi" ".ipynb" ];
    shfmt = mkTool [ (lib.getExe pkgs.shfmt) "-w" "$FILE" ] [ ".sh" ".bash" ];
    typstyle = mkTool [ (lib.getExe pkgs.typstyle) "--inplace" "$FILE" ] [ ".typ" ];
    uv = {
      disabled = true;
    };
  };

  typstSkillSrc = fetchGit {
    url = "https://github.com/lucifer1004/claude-skill-typst.git";
    ref = "main";
    rev = "aefb3d2c978bba3189702ded2654a285428851c7";
  };

  openaiSkillsSrc = fetchGit {
    url = "https://github.com/openai/skills.git";
    ref = "main";
    rev = "736f600bf6ecbc000c04f1d2710b990899f28903";
  };

  opencodeNotifierDarwinFallback = pkgs.writeShellScript "opencode-notifier-darwin-fallback" ''
    event="''${1:-}"
    message="''${2:-}"

    case "$event" in
      permission|question|plan_exit|complete|error) ;;
      *) exit 0 ;;
    esac

    is_ghostty=0

    case "''${TERM_PROGRAM-}" in
      ghostty|Ghostty) is_ghostty=1 ;;
    esac

    case "''${LC_TERMINAL-}" in
      ghostty|Ghostty) is_ghostty=1 ;;
    esac

    case "''${TERM-}" in
      *ghostty*|*GHOSTTY*) is_ghostty=1 ;;
    esac

    if [ -n "''${TMUX-}" ] && command -v tmux >/dev/null 2>&1; then
      tmux_client_term="$(tmux display-message -p '#{client_termname}' 2>/dev/null || true)"
      case "$tmux_client_term" in
        *ghostty*|*GHOSTTY*) is_ghostty=1 ;;
      esac
    fi

    if [ "$is_ghostty" -eq 1 ]; then
      exit 0
    fi

    HM_OPENCODE_NOTIFY_TITLE="OpenCode ($event)" \
    HM_OPENCODE_NOTIFY_BODY="$message" \
      /usr/bin/osascript -e 'display notification (system attribute "HM_OPENCODE_NOTIFY_BODY") with title (system attribute "HM_OPENCODE_NOTIFY_TITLE")' >/dev/null 2>&1 || true
  '';
in
{
  programs.opencode = {
    enable = true;
    skills = {
      typst = "${typstSkillSrc}/skills/typst";
      gh-address-comments = "${openaiSkillsSrc}/skills/.curated/gh-address-comments";
      gh-fix-ci = "${openaiSkillsSrc}/skills/.curated/gh-fix-ci";
      yeet = "${openaiSkillsSrc}/skills/.curated/yeet";
      frontend-skill = "${openaiSkillsSrc}/skills/.curated/frontend-skill";
    };
    settings = {
      autoupdate = false;
      plugin = [
        "opencode-gemini-auth@latest"
        "@mohak34/opencode-notifier@latest"
      ];
      formatter = documentedFormatters;
      lsp = documentedLsp;
      permission = {
        external_directory = {
          "${config.xdg.cacheHome}/**" = "allow";
          "/tmp/**" = "allow";
        };
        read = {
          "/nix/store/**" = "allow";
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

  home.packages = lib.optionals isLinux [ pkgs.libnotify ];

  home.sessionVariables = {
    OPENCODE_EXPERIMENTAL_LSP_TOOLS = 1;
    OPENCODE_EXPERIMENTAL_LSP_TY = 1;
    OPENCODE_DISABLE_LSP_DOWNLOAD = 1;

    OPENCODE_EXPERIMENTAL_OXFMT = 1;

    OPENCODE_ENABLE_EXA = 1;
    OPENCODE_EXPERIMENTAL_EXA = 1;

    OPENCODE_EXPERIMENTAL_PLAN_MODE = 1;
  };
}
