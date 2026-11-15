# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
set -euo pipefail

work_directory="$TMPDIR/python-quality-source"
mkdir "$work_directory"
cp -R @inputs_self_outPath@/. "$work_directory"
chmod -R u+w "$work_directory"
cd "$work_directory"

export RUFF_CACHE_DIR="$TMPDIR/ruff-cache"
export PYTHONPYCACHEPREFIX="$TMPDIR/python-pycache"

# Root discovery respects nested project configurations and excludes submodules,
# whose static analysis belongs to their own checks.
ruff check --no-fix .
ruff format --check .

# `--project .` makes ty discover [tool.ty] in this exact copied
# pyproject.toml. Use Nix Python rather than an impure developer
# virtualenv so the result is reproducible on every system.
ty check --project . --python @checkPython@/bin/python3

# Cover every Python-bearing top-level source tree. Bytecode is redirected
# outside the source tree above.
python3 -m compileall -q flake fuzz homes hosts lib modules overlays scripts site templates tests .github

touch "$out"
