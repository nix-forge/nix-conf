# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
# shellcheck disable=SC2154
mkdir -p "$out/bin"
swiftc -target @swiftTarget@ -parse-as-library @set_default_browser_swift@ -o "$out/bin/set-default-browser"

# Missing arguments return before the helper changes any browser registration.
if "$out/bin/set-default-browser" >usage.log 2>&1; then
  echo "Default browser helper unexpectedly accepted missing arguments" >&2
  exit 1
else
  status=$?
fi
if [[ $status != 2 || $(cat usage.log) != 'usage: set-default-browser APPLICATION_PATH' ]]; then
  cat usage.log >&2
  echo "Default browser helper failed its no-argument usage check" >&2
  exit 1
fi
