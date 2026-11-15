# shellcheck shell=bash
set -euo pipefail
: "${out:?Nix build output path is required}"
export HOME="$TMPDIR/home"
mkdir -p "$HOME" config private user
cp @public@ config/nix.conf
printf 'access-tokens = github.com=synthetic-root-token\n' >private/root.conf
printf 'access-tokens = github.com=synthetic-user-token\n' >user/user.conf
# Public settings must parse when another identity cannot traverse credentials.
chmod 000 private
NIX_CONF_DIR="$PWD/config" NIX_USER_CONF_FILES=/dev/null @python@ @probe@ public @public@
chmod 700 private
NIX_CONF_DIR="$PWD/config" NIX_USER_CONF_FILES="$PWD/private/root.conf" @python@ @probe@ root
NIX_CONF_DIR="$PWD/config" NIX_USER_CONF_FILES="$PWD/user/user.conf" @python@ @probe@ user
mkdir -p root-home/.config/nix
printf '# existing operator configuration\n' >root-home/.config/nix/nix.conf
if bash @script@ "$PWD/root-home" "$PWD/private/root.conf"; then
  echo 'Root configuration collision was incorrectly accepted' >&2
  exit 1
fi
test "$(cat root-home/.config/nix/nix.conf)" = '# existing operator configuration'
rm root-home/.config/nix/nix.conf
bash @script@ "$PWD/root-home" "$PWD/private/root.conf"
test "$(readlink root-home/.config/nix/nix.conf)" = "$PWD/private/root.conf"
bash @script@ "$PWD/root-home" "$PWD/private/root.conf"
touch "$out"
