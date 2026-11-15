# shellcheck shell=bash
app=@lib_escapeShellArg_appPath@
identity=@lib_escapeShellArg_cfg_signingIdentity@
run /bin/wait4path "$app"
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$identity"; then
  printf 'OCR Capture signing identity is unavailable: %s\n' "$identity" >&2
  exit 1
fi
run /usr/bin/codesign --force --options runtime --sign "$identity" "$app"
run /usr/bin/codesign --verify --strict --verbose=2 "$app"
