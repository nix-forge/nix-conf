{
  config,
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  typstSkillSrc = fetchGit {
    url = "https://github.com/lucifer1004/claude-skill-typst.git";
    ref = "main";
    rev = "23905d4bc38042038b9b7032c3d41e19bf88191a";
  };

  opencodeCursorPkg = self.packages.${system}.opencode-cursor;
  baseOpencodeConfigPath = "${config.xdg.configHome}/opencode/opencode.json";
  runtimeOpencodeConfigPath = "${config.xdg.stateHome}/opencode/opencode.json";
in
{
  programs.opencode = {
    enable = true;
    skills.typst = "${typstSkillSrc}/skills/typst";
    settings = {
      autoupdate = false;
      plugin = [
        "cursor-acp"
        "opencode-gemini-auth@latest"
        "@simonwjackson/opencode-direnv"
        "@mohak34/opencode-notifier@latest"
        "plan-mode-notify"
      ];
      provider.cursor-acp = {
        name = "Cursor";
        npm = "@ai-sdk/openai-compatible";
        options.baseURL = "http://127.0.0.1:32124/v1";
        models = { };
      };
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

  home.packages = [ opencodeCursorPkg ];

  xdg.configFile."opencode/plugin/cursor-acp.js".source =
    "${opencodeCursorPkg}/lib/opencode-cursor/dist/plugin-entry.js";

  xdg.configFile."opencode/plugin/plan-mode-notify.ts".source = ./opencode-plan-mode-notify.ts;

  xdg.configFile."opencode/opencode-notifier.json".text = builtins.toJSON {
    sound = false;
    notification = true;
    timeout = 5;
    showProjectName = true;
    showSessionTitle = false;
    showIcon = true;
    suppressWhenFocused = true;
    enableOnDesktop = false;
    notificationSystem = "osascript";
    command.enabled = false;
    events = {
      permission = {
        sound = false;
        notification = true;
        command = false;
      };
      complete = {
        sound = false;
        notification = true;
        command = false;
      };
      error = {
        sound = false;
        notification = true;
        command = false;
      };
      question = {
        sound = false;
        notification = false;
        command = false;
      };
      subagent_complete = {
        sound = false;
        notification = false;
        command = false;
      };
      user_cancelled = {
        sound = false;
        notification = false;
        command = false;
      };
    };
  };

  home.activation.syncOpencodeRuntimeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        state_dir="${config.xdg.stateHome}/opencode"
        mkdir -p "$state_dir"

        if [ ! -f "${baseOpencodeConfigPath}" ]; then
          exit 0
        fi

        ${lib.getExe pkgs.python3} - <<'PY'
    import json
    from pathlib import Path

    base_path = Path(${builtins.toJSON baseOpencodeConfigPath})
    runtime_path = Path(${builtins.toJSON runtimeOpencodeConfigPath})


    def read_json(path: Path):
        if not path.exists():
            return {}
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except Exception:
            return {}


    base_cfg = read_json(base_path)
    runtime_cfg = read_json(runtime_path)

    runtime_models = (
        runtime_cfg.get("provider", {})
        .get("cursor-acp", {})
        .get("models")
    )

    if isinstance(runtime_models, dict):
        provider = base_cfg.setdefault("provider", {})
        cursor_provider = provider.setdefault("cursor-acp", {})
        declared_models = cursor_provider.get("models")
        merged_models = dict(declared_models) if isinstance(declared_models, dict) else {}
        merged_models.update(runtime_models)
        cursor_provider["models"] = merged_models

    runtime_path.write_text(json.dumps(base_cfg, indent=2) + "\n", encoding="utf-8")
    PY
  '';

  home.sessionVariables = {
    OPENCODE_CONFIG = runtimeOpencodeConfigPath;

    OPENCODE_EXPERIMENTAL_LSP_TOOLS = 1;
    OPENCODE_EXPERIMENTAL_LSP_TY = 1;
    OPENCODE_DISABLE_LSP_DOWNLOAD = 1;

    OPENCODE_ENABLE_EXA = 1;
    OPENCODE_EXPERIMENTAL_EXA = 1;

    OPENCODE_EXPERIMENTAL_PLAN_MODE = 1;
  };
}
