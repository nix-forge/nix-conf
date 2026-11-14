# shellcheck shell=bash
# VSCode Copilot Minimal Integration
if [[ ${COPILOT:-} == "1" ]]; then
  # Set minimal PS1
  PS1='copilot:\w\$ '

  # VS Code Shell Integration. Resolve the script with the pinned
  # executable and only source an existing regular file.
  __vscode_executable=@vscode@
  if [[ ${TERM_PROGRAM:-} == "vscode" && -n $__vscode_executable ]]; then
    if __vscode_shell_integration="$("$__vscode_executable" --locate-shell-integration-path bash 2>/dev/null)"; then
      if [[ -f $__vscode_shell_integration && -r $__vscode_shell_integration ]]; then
        builtin source -- "$__vscode_shell_integration"
      fi
    fi
    unset __vscode_shell_integration
  fi
  unset __vscode_executable
  __vscode_direnv_enabled=@direnvEnabled@
  if [[ $__vscode_direnv_enabled == true ]]; then
    builtin source -- @direnvBashInit@
  fi
  unset __vscode_direnv_enabled
  return
fi
