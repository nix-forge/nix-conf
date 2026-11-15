# shellcheck shell=bash
# The normal fzf Bash loader is incompatible with ble.sh. Use the pinned
# fzf scripts through ble.sh and defer their parse cost until the shell is
# idle. Atuin owns Ctrl-R search in Emacs mode.
_ble_contrib_fzf_base=@config_programs_fzf_package@/share/fzf
ble-import -d integration/fzf-completion
ble-import -d integration/fzf-key-bindings -C '
  # fzf installs Ctrl-R as a direct ble.sh widget. Replace it with an
  # editable Atuin widget so ble.sh exports and restores READLINE_LINE
  # and READLINE_POINT. enter_accept is disabled, so no accept-line
  # macro chain is required.
  if declare -F __atuin_history &>/dev/null; then
    ble-bind -m emacs -x C-r "__atuin_history --keymap-mode=emacs"
  fi
'

# Keep the normal ble.sh completion menu on Tab. Shift-Tab opens the fzf
# selector when a large or descriptive candidate set benefits from it.
ble-import -d integration/fzf-menu -C '
  bleopt integration_fzf_menu_enabled=
  ble-bind -m emacs -f S-TAB fzf-menu-complete
'
