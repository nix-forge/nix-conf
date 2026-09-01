#!@bash@
# shellcheck shell=bash
set -euo pipefail

export PYTHONPYCACHEPREFIX="${TMPDIR:?}/python-pycache"
exec @python@ -m compileall -q homes modules scripts pkgs
