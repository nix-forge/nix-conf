# shellcheck shell=bash
mapfile -d "" -t stylesheets < <(git ls-files -z -- '*.css')
if ((${#stylesheets[@]} > 0)); then
  stylelint --config .stylelintrc.json --max-warnings 0 "${stylesheets[@]}"
fi
