# shellcheck shell=bash disable=SC2154
# pname, src and out are supplied by the package build environment.
# These sandbox-compatible regression checks retain strict sandboxing.
# Apple's independent deep/strict verifier remains the native acceptance check.
case "$pname" in
aerospace)
  # The failure was caused by mutating an originally valid signed binary.
  diff -r "$src/AeroSpace.app" "$out/Applications/AeroSpace.app"
  ;;
zoom)
  # The installer payload is already signed, including nested helpers.
  diff -r zoom.us.app "$out/Applications/zoom.us.app"
  ;;
signal-desktop)
  checkDirectory="$(mktemp -d)"
  cp -R "$out/Applications/Signal.app" "$checkDirectory/Signal.app"
  chmod -R u+w "$checkDirectory/Signal.app"
  # The same scoped signing command is supplied by the package override.
  python3 "$signalSignatureSigner" "$checkDirectory/Signal.app" "$src/build"
  diff -r "$out/Applications/Signal.app" "$checkDirectory/Signal.app"
  rm -r "$checkDirectory"
  ;;
*)
  printf 'Unexpected application signature repair: %s\n' "$pname" >&2
  exit 1
  ;;
esac
