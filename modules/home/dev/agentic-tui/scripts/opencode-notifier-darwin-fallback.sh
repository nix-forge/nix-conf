#!@bash@
# shellcheck shell=bash
event="${1:-}"
message="${2:-}"

case "$event" in
permission | question | plan_exit | complete | error) ;;
*) exit 0 ;;
esac

is_ghostty=0
case "${TERM_PROGRAM-}" in ghostty | Ghostty) is_ghostty=1 ;; esac
case "${LC_TERMINAL-}" in ghostty | Ghostty) is_ghostty=1 ;; esac
case "${TERM-}" in *ghostty* | *GHOSTTY*) is_ghostty=1 ;; esac

if [ -n "${TMUX-}" ] && command -v tmux >/dev/null 2>&1; then
  tmux_client_term="$(tmux display-message -p '#{client_termname}' 2>/dev/null || true)"
  case "$tmux_client_term" in *ghostty* | *GHOSTTY*) is_ghostty=1 ;; esac
fi

[ "$is_ghostty" -eq 1 ] && exit 0

HM_OPENCODE_NOTIFY_TITLE="OpenCode ($event)" \
  HM_OPENCODE_NOTIFY_BODY="$message" \
  /usr/bin/osascript -e 'display notification (system attribute "HM_OPENCODE_NOTIFY_BODY") with title (system attribute "HM_OPENCODE_NOTIFY_TITLE")' >/dev/null 2>&1 || true
