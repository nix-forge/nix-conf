{
  lib,
  pkgs,
  config,
  ...
}:
let
  # Determine the OS platform (linux or osx)
  os = if pkgs.stdenv.isLinux then "linux" else "osx";
  # Copilot chat terminal profiles for both platforms
  copilotTerminalProfileConfig = {
    "chat.tools.terminal.terminalProfile.${os}" = {
      path = lib.getExe' pkgs.bashInteractive "bash";
      args = [
        "--noprofile"
        "--norc"
      ];
      env = {
        NO_COLOR = "1";
        CLICOLOR = "0";
      };
    };
  };

  # User shell configuration (only if SHELL is defined)
  userShellConfig = lib.mkIf (lib.hasAttr "SHELL" config.home.sessionVariables) (
    let
      shellPath = config.home.sessionVariables.SHELL;
      shellName = lib.last (lib.splitString "/" shellPath);
    in
    {
      # Define extra shells
      "terminal.integrated.profiles.${os}" = {
        ${shellName} = {
          path = shellPath;
          overrideName = true;
          icon =
            if shellName == "bash" then
              "terminal-bash"
            else if shellName == "nu" then
              "chevron-right"
            else
              "terminal";
        }
        // lib.optionalAttrs (shellName == "nu") { args = [ "--login --interactive" ]; };
      };

      # set the integrated terminal to use SHELL so make sure SHELL is set correctly
      "terminal.integrated.defaultProfile.${os}" = shellName;

      # set the default shell for automation tasks to a fully POSIX compliant shell
      "terminal.integrated.automationProfile.${os}" = {
        "path" = lib.getExe' pkgs.bashInteractive "sh";
        "args" = [ "--login" ];
      };
    }
  );
in
# Merge Copilot profiles with user shell configuration
{
  "terminal.integrated.shellIntegration.enabled" = true;
}
// copilotTerminalProfileConfig
// userShellConfig
