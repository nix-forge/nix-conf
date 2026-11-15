# shellcheck shell=bash
# Navidrome's v0.64.0-0.64.1 plugin CLI accepts usernames, but its permission
# check compares stored entries with account IDs. Remove this workaround when
# the CLI resolves usernames to IDs before storing plugin permissions.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "expected two managed usernames" >&2
  exit 2
fi

jq --compact-output --exit-status \
  --arg listener "$1" \
  --arg feishin "$2" '
    if type == "array" then . else error("invalid Navidrome account list") end
    | . as $accounts
    | [$listener, $feishin]
    | map(
        . as $name
        | [$accounts[] | select(.username == $name)]
        | if length == 1 then .[0].id
          else error("expected exactly one managed Navidrome account") end
        | if type == "string" and length > 0 then .
          else error("managed Navidrome account has no ID") end
      )
    | if .[0] != .[1] then .
      else error("managed Navidrome accounts share an ID") end
  '
