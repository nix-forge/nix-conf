# shellcheck shell=bash
set -euo pipefail
umask 077

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}
[[ $EUID == 0 ]] || fail 'Run this command as root at the physical console.'
root_device=/dev/disk/by-partlabel/NIXOS-CRYPTROOT
data_device=/dev/disk/by-partlabel/NIXOS-CRYPTDATA
cryptsetup isLuks --type luks2 "$root_device" || fail 'The encrypted layout has not been installed.'
root_source=$(findmnt -n -o SOURCE /)
[[ $root_source == /dev/mapper/cryptroot* ]] || fail 'Boot the installed encrypted root before enrollment.'
key_file=@dataKeyFile@
measured_boot=@measuredBoot@
recovery_directory=/var/lib/desktop-storage/recovery

signed_boot() {
  python3 - <<'PY'
from pathlib import Path
root = Path('/sys/firmware/efi/efivars')
values = list(root.glob('SecureBoot-*'))
if len(values) != 1 or values[0].read_bytes()[4:5] != b'\x01':
    raise SystemExit('Firmware Secure Boot must be enabled before hardware enrollment.')
PY
}

case "${1:-help}" in
data-key)
  cryptsetup isLuks --type luks2 "$data_device" || fail 'The data volume is not LUKS2.'
  install -d -m 700 "$(dirname "$key_file")"
  if [[ ! -e $key_file ]]; then
    # Do not overwrite or discard a candidate key after an ambiguous failure.
    (
      set -o noclobber
      head -c 64 /dev/urandom >"$key_file"
    )
  fi
  [[ ! -L $key_file && -f $key_file ]] || fail 'The data key must be a regular file.'
  [[ "$(stat -c '%u:%a' "$key_file")" == 0:600 ]] || fail 'The data key must be root-owned with mode 0600.'
  if cryptsetup open --test-passphrase --key-file "$key_file" "$data_device"; then
    printf '%s\n' 'The existing data key is already enrolled.'
  else
    printf '%s\n' 'Enter the existing data-volume recovery passphrase when cryptsetup asks.'
    cryptsetup luksAddKey "$data_device" "$key_file"
    cryptsetup open --test-passphrase --key-file "$key_file" "$data_device"
  fi
  ;;
tpm-pin)
  signed_boot
  [[ $measured_boot == true ]] || fail 'Boot a generation with managed measured boot enabled first.'
  [[ -s @pcrlockPolicy@ ]] || fail 'The managed PCR policy is missing.'
  @pcrlockExecutable@ is-supported
  if cryptsetup luksDump --dump-json-metadata "$root_device" | jq -e '.tokens | any(.type == "systemd-tpm2")' >/dev/null; then
    fail 'A TPM token already exists. Review it and use the documented recovery procedure before replacing it.'
  fi
  printf '%s\n' 'First test the recovery passphrase. This does not alter its slot.'
  cryptsetup open --test-passphrase "$root_device"
  systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrlock=@pcrlockPolicy@ "$root_device"
  cryptsetup luksDump --dump-json-metadata "$root_device" | jq -e '.tokens | any(.type == "systemd-tpm2" and ."tpm2-pin" == true)' >/dev/null
  ;;
fido2)
  signed_boot
  printf '%s\n' 'Connect exactly one intended YubiKey. Repeat for the second key after testing the first.'
  cryptsetup open --test-passphrase "$root_device"
  systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes "$root_device"
  ;;
headers)
  install -d -m 700 "$recovery_directory"
  destination=$(mktemp -d "$recovery_directory/headers.XXXXXXXX")
  cryptsetup luksHeaderBackup "$root_device" --header-backup-file "$destination/root.header"
  cryptsetup luksHeaderBackup "$data_device" --header-backup-file "$destination/data.header"
  printf '%s\n' 'Header backups created in the protected recovery directory. Copy them to independent encrypted storage.'
  ;;
*)
  printf '%s\n' 'Usage: desktop-storage-enroll {data-key|tpm-pin|fido2|headers}'
  printf '%s\n' 'No command formats drives, resets a key, removes recovery slots, or changes firmware.'
  ;;
esac
