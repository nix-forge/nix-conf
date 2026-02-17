# shellcheck disable=SC2148
readonly EXPECTED_TYPE='@expectedHostKeyType@'
readonly EXPECTED_KEY='@expectedHostKeyBody@'
readonly HOST_KEY_PUB_PATH='@hostKeyPubPath@'
readonly HOST_NAME='@hostName@'
readonly INSTALL_GUIDE='@installGuidePath@'

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  printf 'Host: %s\n' "${HOST_NAME}" >&2
  printf 'Expected host key: %s %s\n' "${EXPECTED_TYPE}" "${EXPECTED_KEY}" >&2
  printf 'Install guide: %s\n' "${INSTALL_GUIDE}" >&2
  exit 1
}

if [[ ! -r ${HOST_KEY_PUB_PATH} ]]; then
  fail "Missing host public key at ${HOST_KEY_PUB_PATH}. Preseed the host keypair before install."
fi

if [[ ! -s ${HOST_KEY_PUB_PATH} ]]; then
  fail "Empty host public key at ${HOST_KEY_PUB_PATH}. Preseed a valid host keypair before install."
fi

read -r actual_type actual_key _ <"${HOST_KEY_PUB_PATH}" || true
if [[ -z ${actual_type:-} || -z ${actual_key:-} ]]; then
  fail "Could not parse ${HOST_KEY_PUB_PATH} (expected '<type> <base64> [comment]')."
fi

if [[ ${actual_type} != "${EXPECTED_TYPE}" || ${actual_key} != "${EXPECTED_KEY}" ]]; then
  printf 'Configured key does not match the preseeded host key.\n' >&2
  printf 'Configured: %s %s\n' "${EXPECTED_TYPE}" "${EXPECTED_KEY}" >&2
  printf 'Actual:     %s %s\n' "${actual_type}" "${actual_key}" >&2
  fail "Host key mismatch. Regenerate/rekey secrets for this host pubkey or preseed the matching private key."
fi

printf 'agenix preflight: host key matches configured recipient for %s.\n' "${HOST_NAME}"
