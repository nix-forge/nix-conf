# shellcheck shell=bash
# Nix supplies the output directory.
# shellcheck disable=SC2154
export PYTHONPATH="@testSource@/tests${PYTHONPATH:+:$PYTHONPATH}"
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_CONFIG_HOME="$TMPDIR/config"
export XDG_DATA_HOME="$TMPDIR/data"
mkdir -p "$out"
for suite in digits multilingual private-use apple-stack apple-platform missing-named-stack compatibility emoji-presentation; do
  if ! python @testSource@/tests/browsers/check_font_rendering.py --suite "$suite" --browser @lib_getExe_pkgs_firefox@ --user-content-css @modules_home_browsers_shared_emoji_presentation_css@ --output "$out/$suite"; then
    for evidence in "$out/$suite"/*.json; do
      if test -f "$evidence"; then cat "$evidence"; fi
    done
    exit 1
  fi
done
