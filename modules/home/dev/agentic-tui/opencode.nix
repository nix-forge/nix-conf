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
in
{
  programs.opencode = {
    enable = true;
    skills.typst = "${typstSkillSrc}/skills/typst";
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
    // lib.optionalAttrs isDarwin { notificationSystem = "osascript"; }
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
