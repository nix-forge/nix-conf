# shellcheck disable=SC2148

readonly DEFAULTBROWSER_EXE='@defaultBrowserExe@'
readonly ZEN_APP='@zenAppPath@'
readonly LSREGISTER_EXE='@lsregisterExe@'
readonly PLISTBUDDY_EXE='@plistBuddyExe@'
readonly AWK_EXE='@awkExe@'
readonly DEFAULTBROWSER_HANDLER='zen'

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

extract_registered_entry() {
  # shellcheck disable=SC2016
  "${AWK_EXE}" -v app_path="${ZEN_APP}" '
    BEGIN {
      app_path_re = app_path
      gsub(/[][\\.^$*+?(){}|]/, "\\\\&", app_path_re)
    }
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
      if ($0 ~ ("path:[[:space:]]+" app_path_re " \\(")) {
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

printf 'refreshing Zen Browser Launch Services registration...\n' >&2

if [ "${ZEN_APP}" = 'null' ] || [ ! -d "${ZEN_APP}" ]; then
  fail "managed Zen Browser.app was not found at ${ZEN_APP}"
fi

zen_info_plist="${ZEN_APP}/Contents/Info.plist"
expected_bundle_id="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleIdentifier' "${zen_info_plist}")"
expected_bundle_version="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleVersion' "${zen_info_plist}")"
expected_short_version="$("${PLISTBUDDY_EXE}" -c 'Print :CFBundleShortVersionString' "${zen_info_plist}")"

"${LSREGISTER_EXE}" -f "${ZEN_APP}"

registered_entry="$(extract_registered_entry)"
if [ -z "${registered_entry}" ]; then
  fail "Launch Services does not have a registration entry for ${ZEN_APP}"
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
  fail "Launch Services registered bundle id ${registered_bundle_id} for ${ZEN_APP}, expected ${expected_bundle_id}"
fi

if [ "${registered_bundle_version}" != "${expected_bundle_version}" ]; then
  fail "Launch Services still reports Zen Browser bundle version ${registered_bundle_version} at ${ZEN_APP}, expected ${expected_bundle_version} (${expected_short_version})"
fi

printf 'setting Zen Browser as the default browser...\n' >&2
"${DEFAULTBROWSER_EXE}" "${DEFAULTBROWSER_HANDLER}"

available_handlers="$("${DEFAULTBROWSER_EXE}")"
if ! printf '%s\n' "${available_handlers}" | grep -Eq "^\*[[:space:]]+${DEFAULTBROWSER_HANDLER}$"; then
  printf 'current handlers:\n%s\n' "${available_handlers}" >&2
  fail 'failed to set Zen Browser as the default browser'
fi
