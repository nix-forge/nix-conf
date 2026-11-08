# shellcheck shell=bash
protected_default_current="$(@readUserDefault_domain_key@)"
if [ "$protected_default_current" != @lib_escapeShellArg_desired@ ]; then
  echo >&2 "updating protected macOS default @domain@.@key@..."
  if ! /bin/launchctl asuser "$(/usr/bin/id -u -- @user@)" \
    /usr/bin/sudo --user=@user@ -- \
    /usr/bin/defaults write @lib_escapeShellArg_domain@ @lib_escapeShellArg_key@ \
    -bool @boolValue@; then
    echo >&2 "warning: macOS blocked @domain@.@key@; grant the activating terminal Full Disk Access to manage it"
  fi
fi
