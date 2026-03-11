#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULTBROWSER_EXE='@defaultBrowserExe@'
readonly FIREFOX_APP='@firefoxAppPath@'
readonly LSREGISTER_EXE='@lsregisterExe@'
readonly PLISTBUDDY_EXE='@plistBuddyExe@'
readonly AWK_EXE='@awkExe@'

fail() {
	printf 'error: %s\n' "$1" >&2
	exit 1
}

extract_registered_entry() {
	# shellcheck disable=SC2016
	"${AWK_EXE}" -v app_path="${FIREFOX_APP}" '
    $0 ~ /^-+$/ {
      if (block != "" && found) {
        print block
        exit
      }
      block = $0 ORS
      found = 0
      next
    }
    {
      block = block $0 ORS
      if ($0 ~ ("path:[[:space:]]+" app_path " \\(")) {
        found = 1
      }
    }
    END {
      if (block != "" && found) {
        print block
      }
    }
  ' < <("${LSREGISTER_EXE}" -dump)
}

printf 'refreshing Firefox Launch Services registration...\n' >&2

if [ "${FIREFOX_APP}" = 'null' ] || [ ! -d "${FIREFOX_APP}" ]; then
	fail "managed Firefox.app was not found at ${FIREFOX_APP}"
fi

firefox_info_plist="${FIREFOX_APP}/Contents/Info.plist"
expected_bundle_id="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleIdentifier' "${firefox_info_plist}")"
expected_bundle_version="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleVersion' "${firefox_info_plist}")"
expected_short_version="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleShortVersionString' "${firefox_info_plist}")"

"${LSREGISTER_EXE}" -f "${FIREFOX_APP}"

registered_entry="$(extract_registered_entry)"
if [ -z "${registered_entry}" ]; then
	fail "Launch Services does not have a registration entry for ${FIREFOX_APP}"
fi

registered_bundle_id="$(
	printf '%s\n' "${registered_entry}" | sed -n 's/^[[:space:]]*identifier:[[:space:]]*//p' | head -n 1
)"
registered_bundle_version="$(
	printf '%s\n' "${registered_entry}" |
		sed -n 's/^[[:space:]]*version:[[:space:]]*//p' |
		sed 's/[[:space:]]*(.*$//' |
		head -n 1
)"

if [ "${registered_bundle_id}" != "${expected_bundle_id}" ]; then
	fail "Launch Services registered bundle id ${registered_bundle_id} for ${FIREFOX_APP}, expected ${expected_bundle_id}"
fi

if [ "${registered_bundle_version}" != "${expected_bundle_version}" ]; then
	fail "Launch Services still reports Firefox bundle version ${registered_bundle_version} at ${FIREFOX_APP}, expected ${expected_bundle_version} (${expected_short_version})"
fi

printf 'setting Firefox as the default browser...\n' >&2
"${DEFAULTBROWSER_EXE}" firefox

available_handlers="$("${DEFAULTBROWSER_EXE}")"
if ! printf '%s\n' "${available_handlers}" | grep -Eq '^\*[[:space:]]+firefox$'; then
	printf 'current handlers:\n%s\n' "${available_handlers}" >&2
	fail 'failed to set Firefox as the default browser'
fi
