#!@bash@
# shellcheck shell=bash
set -euo pipefail

cache="$(@mktemp@ -d)"
trap '@rm@ -rf -- "$cache"' EXIT
export PYTHONPYCACHEPREFIX="$cache"
@python@ -m compileall -q homes modules scripts tests pkgs
