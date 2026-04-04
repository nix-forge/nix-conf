{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

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

  anthropicSkillsSrc = fetchGit {
    url = "https://github.com/anthropics/skills.git";
    ref = "main";
    rev = "98669c11ca63e9c81c11501e1437e5c47b556621";
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
      frontend-design = "${openaiSkillsSrc}/skills/frontend-design";
    };
    settings = {
      autoupdate = false;
      plugin = [
        "opencode-gemini-auth@latest"
        "@mohak34/opencode-notifier@latest"
      ];
      formatter.typstyle = {
        command = [
          (lib.getExe pkgs.typstyle)
          "--inplace"
          "$FILE"
        ];
        extensions = [ ".typ" ];
      };
      lsp = {
        pyright.disabled = true;
        tinymist = {
          command = [
            (lib.getExe pkgs.tinymist)
            "lsp"
          ];
          extensions = [
            ".typ"
            ".typc"
          ];
        };
        ty = {
          command = [
            (lib.getExe pkgs.uv)
            "run"
            "ty"
            "server"
          ];
          extensions = [
            ".py"
            ".pyi"
          ];
        };
      };
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
