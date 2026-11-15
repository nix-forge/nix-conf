{
  config,
  lib,
  myLib,
  pkgs,
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

  opencodeNotifierDarwinFallback = writeBashTemplate {
    name = "opencode-notifier-darwin-fallback";
    src = ./scripts/opencode-notifier-darwin-fallback.sh;
    replacements.bash = lib.getExe pkgs.bash;
  };
in
{
  imports = [ ./agent-skills.nix ];

  programs.opencode.context = lib.mkMerge [
    (lib.mkAfter "OpenCode V2 does not run language servers or provide LSP diagnostics. Verify changes with the project's declared lint, typecheck and compiler commands.")
    (lib.mkIf (config.programs.dev-worktree.enable or false) (
      lib.mkAfter config.programs.dev-worktree.instructions
    ))
  ];

  programs.opencode = {
    enable = true;
    skills = {
      typst = "${typstSkillSrc}/skills/typst";
    };
    settings = {
      # Nix manages updates via the pinned package; never let opencode self-update
      # and fight the store.
      update = "disable";
      # Lock the default so an upstream default change cannot start uploading
      # sessions. Use /share explicitly if sharing is ever needed.
      share = "manual";
      # V2 plugins use @opencode/plugin. The SDK itself is not a runtime
      # extension, and the old @opencode-ai/plugin@CLI_VERSION did not exist.
      plugins = [
        "opencode-gemini-auth@2.0.1"
        "@mohak34/opencode-notifier@1.1.2"
      ];
      formatter = documentedFormatters;
      # Ordered V2 rules: preserve the existing full-access default and
      # file exceptions. Specific denies follow the general allow.
      permissions = [
        {
          action = "*";
          resource = "*";
          effect = "allow";
        }
        {
          action = "read";
          resource = "*.env";
          effect = "deny";
        }
        {
          action = "read";
          resource = "*.env.*";
          effect = "deny";
        }
        {
          action = "read";
          resource = "*.env.example";
          effect = "allow";
        }
      ]
      ++
        map
          (resource: {
            action = "read";
            inherit resource;
            effect = "deny";
          })
          [
            "${config.home.homeDirectory}/.ssh/**"
            "${config.home.homeDirectory}/.gnupg/**"
            "${config.xdg.dataHome}/opencode/auth.json"
            "${config.xdg.dataHome}/opencode/mcp-auth.json"
          ];
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

}
