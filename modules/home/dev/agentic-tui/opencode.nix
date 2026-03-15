{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
      plugin = [
        "opencode-gemini-auth@latest"
      ];
    };
  };

  home.sessionVariables = {
    OPENCODE_EXPERIMENTAL_LSP_TOOLS = 1;
    OPENCODE_EXPERIMENTAL_LSP_TY = 1;

    OPENCODE_ENABLE_EXA = 1;
    OPENCODE_EXPERIMENTAL_EXA = 1;

    OPENCODE_EXPERIMENTAL_PLAN_MODE = 1;
  };
}
