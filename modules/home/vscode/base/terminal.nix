{
  lib,
  myLib,
  pkgs,
  config,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  vscode = lib.escapeShellArg (
    if config.programs.vscode.enable && config.programs.vscode.package != null then
      lib.getExe config.programs.vscode.package
    else
      ""
  );
  direnvBashInit = pkgs.runCommandLocal "vscode-direnv-bash-init" { } ''
    ${lib.getExe config.programs.direnv.package} hook bash > "$out"
    ${lib.getExe config.programs.bash.package} -n "$out"
  '';
in
{
  programs.vscode.profiles.default.userSettings =
    let
      os = if pkgs.stdenv.hostPlatform.isLinux then "linux" else "osx";
    in
    lib.mkMerge [
      # Terminal profiles
      {
        "terminal.integrated.shellIntegration.enabled" = true;

        # Ctrl+J runs a multiline ble.sh command when the terminal has focus.
        # Elsewhere it retains VS Code's panel toggle. Ctrl+` still toggles
        # the terminal from either context.
        "terminal.integrated.commandsToSkipShell" = [ "-workbench.action.togglePanel" ];

        # VS Code otherwise treats Ctrl+K as a chord prefix before Bash can
        # use it to delete from the cursor to the end of the line. Chords
        # remain available in editors and other non-terminal views.
        "terminal.integrated.allowChords" = false;
      }
      (lib.mkIf (lib.hasAttr "SHELL" config.home.sessionVariables) (
        let
          shellPath = config.home.sessionVariables.SHELL;
          # Attribute names cannot carry Nix store-path context, while the
          # executable path needs to retain it for the generated JSON.
          shellName = builtins.unsafeDiscardStringContext (lib.last (lib.splitString "/" shellPath));
        in
        {
          # Define terminal profiles for all enabled shells
          "terminal.integrated.profiles.${os}" = {
            ${shellName} = {
              path = shellPath;
              icon = if shellName == "nu" then "chevron-right" else "terminal-bash";
              overrideName = true;
              args = [
                "--login"
                "-i"
              ];
            };
          };

          "terminal.integrated.defaultProfile.${os}" = shellName;
        }
      ))
      {
        # Automation needs a deterministic Bash without login files, prompts,
        # aliases, or interactive hooks.
        "terminal.integrated.automationProfile.${os}" = {
          path = lib.getExe pkgs.bashInteractive;
          args = [
            "--noprofile"
            "--norc"
          ];
        };
      }
      {
        # set the default shell for Copilot
        "chat.tools.terminal.terminalProfile.${os}" = {
          path = lib.getExe' pkgs.bashInteractive "bash";
          args = [
            "--login"
            "-i"
          ];
          env = {
            COPILOT = "1";
          };
        };
      }

    ];
  programs.bash.initExtra = lib.mkOrder 10 (
    (checkedShellText {
      name = "copilot-shell-integration";
      text =
        myLib.templates.renderText
          {
            name = "copilot-shell-integration.sh";
            text = ''
              # shellcheck shell=bash
              # VSCode Copilot Minimal Integration
              if [[ ''${COPILOT:-} == "1" ]]; then
                # Set minimal PS1
                PS1='copilot:\w\$ '

                # VS Code Shell Integration. Resolve the script with the pinned
                # executable and only source an existing regular file.
                __vscode_executable=@vscode@
                if [[ ''${TERM_PROGRAM:-} == "vscode" && -n $__vscode_executable ]]; then
                  if __vscode_shell_integration="$("$__vscode_executable" --locate-shell-integration-path bash 2>/dev/null)"; then
                    if [[ -f $__vscode_shell_integration && -r $__vscode_shell_integration ]]; then
                      # ShellCheck has no access to the path returned by VS Code at runtime.
                      # shellcheck source=/dev/null
                      builtin source -- "$__vscode_shell_integration"
                    fi
                  fi
                  unset __vscode_shell_integration
                fi
                unset __vscode_executable
                __vscode_direnv_enabled=@direnvEnabled@
                if [[ $__vscode_direnv_enabled == true ]]; then
                  # The generated direnv integration belongs to the pinned package.
                  # shellcheck source=/dev/null
                  builtin source -- @direnvBashInit@
                fi
                unset __vscode_direnv_enabled
                return
              fi
            '';
          }
          {
            inherit vscode;
            direnvEnabled = lib.boolToString config.programs.direnv.enable;
            direnvBashInit = lib.escapeShellArg (
              if config.programs.direnv.enable then "${direnvBashInit}" else ""
            );
          };
    })
  );
}
