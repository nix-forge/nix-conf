#!@bash@
# shellcheck shell=bash
set -euo pipefail

cache="$(@mktemp@ -d)"
trap '@rm@ -rf -- "$cache"' EXIT
export PYTHONPYCACHEPREFIX="$cache"
@python@ -m compileall -q flake fuzz homes hosts lib modules overlays scripts site templates tests .github
