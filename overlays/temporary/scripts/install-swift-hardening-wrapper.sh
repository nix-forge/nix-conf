# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
# The upstream package makes swiftc a symlink to swift-driver. Keep the
# driver in place, and add flags only to compiler invocations.
test "$(readlink "$out/bin/swiftc")" = swift-driver
chmod u+w "$out/bin"
rm "$out/bin/swiftc"
sed 's/^  //' >"$out/bin/swiftc" <<'WRAPPER'
  #!@pkgs_bash@/bin/bash
  if [[ -n "${NIX_HARDENING_ENABLE-}" ]]; then
    export NIX_HARDENING_ENABLE_@ccSuffix@="$NIX_HARDENING_ENABLE"
  fi
  source @pkgs_stdenv_cc@/nix-support/add-hardening.sh
  flags=()
  for flag in "${hardeningCFlagsBefore[@]}"; do
    flags+=(-Xcc "$flag")
  done
  for flag in ${NIX_CFLAGS_COMPILE_BEFORE-}; do
    flags+=(-Xcc "$flag")
  done
  for flag in "${hardeningCFlagsAfter[@]}"; do
    flags+=(-Xcc "$flag")
  done
  for flag in ${NIX_CFLAGS_COMPILE-}; do
    flags+=(-Xcc "$flag")
  done
  if (( ${NIX_DEBUG:-0} >= 1 )); then
    printf 'Swift Clang flags:' >&2
    printf ' %q' "${hardeningCFlagsBefore[@]}" "${hardeningCFlagsAfter[@]}" >&2
    printf '\n' >&2
  fi
  exec -a "$0" "$(dirname "$0")/swift-driver" "${flags[@]}" "$@"
WRAPPER
chmod +x "$out/bin/swiftc"
chmod u-w "$out/bin"
