#!@bash@
# shellcheck shell=bash
set -euo pipefail

file="$1"
@ruff@ check --fix --exit-zero "$file"
@ruff@ format "$file"
