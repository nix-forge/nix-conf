# shellcheck shell=bash
# Standard Nix derivation variables supply out and the actual extractor path.
# shellcheck disable=SC2154
set -euo pipefail
mkdir -p "fixture/T3 Code (Beta).app/Contents/"{MacOS,Resources,Frameworks}
printf 'signed-byte-fixture\n' >"fixture/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)"
chmod 755 "fixture/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)"
printf 'plist-byte-fixture\n' >"fixture/T3 Code (Beta).app/Contents/Info.plist"
printf 'resource-byte-fixture\n' >"fixture/T3 Code (Beta).app/Contents/Resources/data"
ln -s ../Resources/data "fixture/T3 Code (Beta).app/Contents/Frameworks/relative-link"
src="$PWD/fixture.zip"
(cd fixture && zip -qyr "$src" "T3 Code (Beta).app")
# shellcheck source=overlays/temporary/scripts/t3code-vendor-gui.sh
source "$extractor"
test -x "$out/Applications/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)"
test -L "$out/Applications/T3 Code (Beta).app/Contents/Frameworks/relative-link"
test "$(readlink "$out/Applications/T3 Code (Beta).app/Contents/Frameworks/relative-link")" = ../Resources/data
test ! -e "$out/Applications/T3 Code (Alpha).app"
# The same complete comparison must reject an altered signed resource.
printf 'poison\n' >>"$out/Applications/T3 Code (Beta).app/Contents/Resources/data"
if diff -qr --no-dereference "vendor/T3 Code (Beta).app" "$out/Applications/T3 Code (Beta).app"; then
  printf 'Resource mutation went undetected\n' >&2
  exit 1
fi
# Keep the fixture output faithful after the causal negative control.
cp -a "vendor/T3 Code (Beta).app/Contents/Resources/data" "$out/Applications/T3 Code (Beta).app/Contents/Resources/data"
diff -qr --no-dereference "vendor/T3 Code (Beta).app" "$out/Applications/T3 Code (Beta).app"
