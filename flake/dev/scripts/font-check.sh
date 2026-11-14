# shellcheck shell=bash
export PYTHONPATH="@testSource@/tests${PYTHONPATH:+:$PYTHONPATH}"
if [[ $# -lt 1 ]]; then
  echo "Usage: font-check OUTPUT-DIRECTORY [BROWSER-EXECUTABLE]" >&2
  exit 2
fi
@lib_optionalString_pkgs_stdenv_hostPlatform_isDarwin_if_ge_2@
output=$(realpath -m "$1")
mkdir -p "$output"
export FONTCONFIG_FILE=@collectionConfig@
export XDG_CACHE_HOME
XDG_CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$XDG_CACHE_HOME"' EXIT
export XDG_CONFIG_HOME="$XDG_CACHE_HOME/config"
export XDG_DATA_HOME="$XDG_CACHE_HOME/data"
python @testSource@/tests/fonts/check_selection.py --providers @providers@ --inventory --output "$output/selection.json"
python @testSource@/tests/fonts/check_emoji_coverage.py --emoji-data @emojiData@
@lib_optionalString_pkgs_stdenv_hostPlatform_isLinux_cp_confi@
mkdir -p "$XDG_CACHE_HOME/fontconfig"
du -sb "$XDG_CACHE_HOME/fontconfig" | cut -f1 >"$output/fontconfig-cache-bytes.txt"
if [[ $# -ge 2 ]]; then
  browser=$(realpath "$2")
  for suite in digits multilingual private-use apple-stack apple-platform missing-named-stack compatibility emoji-presentation; do
    python @testSource@/tests/browsers/check_font_rendering.py --suite "$suite" --browser "$browser" --user-content-css @modules_home_browsers_shared_emoji_presentation_css@ --output "$output/$suite"
  done
  python -m zipfile -e @personal_mutant_standard_emoji_compiledFont_src@ "$XDG_CACHE_HOME/artwork"
  python @testSource@/tests/browsers/check_mutant_emoji.py --installed --font @personal_mutant_standard_emoji@/share/fonts/truetype/MutantStandardEmoji.ttf --artwork "$XDG_CACHE_HOME/artwork/emoji" --browser "$browser" --output "$output/mutant"
  @lib_optionalString_pkgs_stdenv_hostPlatform_isLinux_python_t@
fi
