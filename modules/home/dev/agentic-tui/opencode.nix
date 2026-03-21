{
  config,
  lib,
  pkgs,
  ...
}:
let
  typstSkillSrc = fetchGit {
    url = "https://github.com/lucifer1004/claude-skill-typst.git";
    ref = "main";
    rev = "23905d4bc38042038b9b7032c3d41e19bf88191a";
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
        "@simonwjackson/opencode-direnv"
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
        edit = {
          "${config.xdg.cacheHome}/**" = "allow";
          "/tmp/**" = "allow";
        };
        external_directory = {
          "${config.xdg.cacheHome}/**" = "allow";
          "/tmp/**" = "allow";
        };
      };
    };
  };

  home.sessionVariables = {
    OPENCODE_EXPERIMENTAL_LSP_TOOLS = 1;
    OPENCODE_EXPERIMENTAL_LSP_TY = 1;
    OPENCODE_DISABLE_LSP_DOWNLOAD = 1;

    OPENCODE_ENABLE_EXA = 1;
    OPENCODE_EXPERIMENTAL_EXA = 1;

    OPENCODE_EXPERIMENTAL_PLAN_MODE = 1;
  };
}
