# shellcheck shell=bash
if @pkgs_systemd@/lib/systemd/systemd-bless-boot good; then
  exit 0
else
  status="$?"
fi

efi_var=/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
if [[ -r $efi_var ]]; then
  entry_path="$(strings -el "$efi_var")"
  entry_path="${entry_path//\\//}"
  if [[ $entry_path =~ ^/loader/entries/nixos-[[:xdigit:]]{64}\+[0-9]+-[0-9]+\.conf$ ]] &&
    [[ ! -e @esp_path@"$entry_path" ]]; then
    echo "Ignoring stale LoaderBootCountPath for pruned entry: $entry_path" >&2
    exit 0
  fi
fi

exit "$status"
