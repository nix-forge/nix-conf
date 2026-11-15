# shellcheck shell=bash
# shellcheck disable=SC2154
set -euo pipefail
mkdir -p "$out/Applications" "$out/bin"
cp -R "$unsealed/Applications/Handy.app" "$out/Applications/Handy.app"
chmod -R u+w "$out/Applications/Handy.app"
# Source-built, ad-hoc identity; this does not claim vendor notarization.
rcodesign sign "$out/Applications/Handy.app"
ln -s "$out/Applications/Handy.app/Contents/MacOS/handy" "$out/bin/handy"
