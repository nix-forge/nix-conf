# shellcheck shell=bash
# Standard Nix derivation variables supply the reviewed fixed-output archive.
# shellcheck disable=SC2154
set -euo pipefail
unzip -q "$src" -d vendor
test -d "vendor/T3 Code (Beta).app"
mkdir -p "$out/Applications"
cp -a "vendor/T3 Code (Beta).app" "$out/Applications/"
# Compare all file bytes and raw symlink targets, not just the main executable.
diff -qr --no-dereference "vendor/T3 Code (Beta).app" "$out/Applications/T3 Code (Beta).app"
