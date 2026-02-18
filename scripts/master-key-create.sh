#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_ROOT:-}"
if [[ -z ${repo_root} ]]; then
  repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fi

force="${FORCE:-false}"
identity_path="${IDENTITY_PATH:-}"
main_pub_path="${MAIN_PUB_PATH:-${repo_root}/secrets/master-identities/main.pub}"

if [[ -z ${identity_path} ]]; then
  identity_path="${HOME}/.config/agenix/master.agekey"
fi

if [[ ${force} != "true" && ${force} != "false" ]]; then
  echo "Invalid FORCE='${force}'. Use true or false." >&2
  exit 1
fi

if [[ ${identity_path} != /* ]]; then
  echo "identity_path must be an absolute path." >&2
  exit 1
fi

if [[ ${identity_path} == /nix/store/* ]]; then
  echo "identity_path must not point into /nix/store." >&2
  exit 1
fi

identity_dir="$(dirname "${identity_path}")"
install -d -m 0700 "${identity_dir}"
install -d -m 0755 "$(dirname "${main_pub_path}")"

if [[ -e ${identity_path} && ${force} != "true" ]]; then
  echo "Refusing to overwrite existing identity: ${identity_path}" >&2
  echo "Re-run with force=true to rotate intentionally." >&2
  exit 1
fi


tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agenix-master.XXXXXX")"
tmp_identity="${tmp_dir}/master.agekey"
tmp_pub="${tmp_dir}/main.pub"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

umask 077
nix shell nixpkgs#age -c age-keygen -o "${tmp_identity}" >/dev/null
nix shell nixpkgs#age -c age-keygen -y "${tmp_identity}" >"${tmp_pub}"

install -m 0600 "${tmp_identity}" "${identity_path}"

chmod 0600 "${identity_path}"
install -m 0644 "${tmp_pub}" "${main_pub_path}"

echo "Created master identity: ${identity_path}"
echo "Updated public key: ${main_pub_path}"
echo "Next steps:"
echo "  1. Ensure masterIdentityPath matches this identity path in your admin host/home config."
echo "  2. Run: just rekey-update-masterkeys"
echo "  3. Run: just rekey"
