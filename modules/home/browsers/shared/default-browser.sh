#!@bash@
# shellcheck shell=bash

readonly DEFAULTBROWSER_EXE='@defaultBrowserExe@'
readonly SET_DEFAULT_BROWSER_EXE='@setDefaultBrowserExe@'
# These substitutions are shell-escaped literals supplied by Nix.
# shellcheck disable=SC2016
readonly APP_PATH=@appPath@
# shellcheck disable=SC2016
readonly APP_LABEL=@appLabel@
# shellcheck disable=SC2016
readonly HANDLER=@handler@
readonly LSREGISTER_EXE='@lsregisterExe@'
readonly PLISTBUDDY_EXE='@plistBuddyExe@'
readonly AWK_EXE='@awkExe@'

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

extract_registered_entry() {
  "${AWK_EXE}" -v app_path="${APP_PATH}" -f '@registeredBrowserAwk@' < <("${LSREGISTER_EXE}" -dump)
}

if [ ! -d "${APP_PATH}" ]; then
  fail "managed ${APP_LABEL} application was not found at ${APP_PATH}"
fi

info_plist="${APP_PATH}/Contents/Info.plist"
expected_bundle_id="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleIdentifier' "${info_plist}")"
expected_bundle_version="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleVersion' "${info_plist}")"
expected_short_version="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleShortVersionString' "${info_plist}")"

printf 'refreshing %s Launch Services registration...\n' "${APP_LABEL}" >&2
"${LSREGISTER_EXE}" -f "${APP_PATH}"

registered_entry="$(extract_registered_entry)"
if [ -z "${registered_entry}" ]; then
  fail "Launch Services does not have a registration entry for ${APP_PATH}"
fi

registered_bundle_id="$({
  printf '%s\n' "${registered_entry}" |
    sed -n 's/^[[:space:]]*identifier:[[:space:]]*//p' |
    head -n 1
})"
registered_bundle_version="$({
  printf '%s\n' "${registered_entry}" |
    sed -n 's/^[[:space:]]*version:[[:space:]]*//p' |
    sed 's/[[:space:]]*(.*$//' |
    head -n 1
})"

if [ "${registered_bundle_id}" != "${expected_bundle_id}" ]; then
  fail "Launch Services registered bundle id ${registered_bundle_id} for ${APP_PATH}, expected ${expected_bundle_id}"
fi

if [ "${registered_bundle_version}" != "${expected_bundle_version}" ]; then
  fail "Launch Services reports ${APP_LABEL} bundle version ${registered_bundle_version}, expected ${expected_bundle_version} (${expected_short_version})"
fi

printf 'setting %s as the default browser...\n' "${APP_LABEL}" >&2
"${SET_DEFAULT_BROWSER_EXE}" "${APP_PATH}"

is_default_browser() {
  "${DEFAULTBROWSER_EXE}" | grep -Eq "^\\*[[:space:]]+${HANDLER}$"
}

if ! is_default_browser; then
  available_handlers="$("${DEFAULTBROWSER_EXE}")"
  printf 'current handlers:\n%s\n' "${available_handlers}" >&2
  fail "failed to set ${APP_LABEL} as the default browser"
fi
