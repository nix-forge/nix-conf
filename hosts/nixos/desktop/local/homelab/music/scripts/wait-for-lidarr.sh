# shellcheck shell=bash
key="$(@cat@ "$CREDENTIALS_DIRECTORY/lidarr-api-key")"
case "$key" in
"" | *$'\n'* | *$'\r'*)
  echo "Invalid Lidarr API credential" >&2
  exit 1
  ;;
esac
printf 'X-Api-Key: %s\n' "$key" | @curl@
