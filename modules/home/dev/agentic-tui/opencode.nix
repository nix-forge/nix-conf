{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.opencode = {
    enable = true;
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
            "uv"
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
        };
        external_directory = {
          "${config.xdg.cacheHome}/**" = "allow";
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
