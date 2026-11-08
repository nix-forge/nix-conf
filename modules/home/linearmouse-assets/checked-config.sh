# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
# All references must be bundled in the pinned schema, including overrides.
jq -e -f @referencesFilter@ @lib_escapeShellArg_cfg_settingsSchema@ >/dev/null || {
  echo 'LinearMouse settingsSchema must be self-contained; external references are not supported.' >&2
  exit 1
}
check-jsonschema --schemafile @lib_escapeShellArg_cfg_settingsSchema@ @renderedConfig@
cp @renderedConfig@ "$out"
