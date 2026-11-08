# shellcheck shell=bash
current_host_default="$(@readCurrentHostUserDefault_domain_key@)"
if [ "$current_host_default" != @lib_escapeShellArg_desired@ ]; then
  /bin/launchctl asuser "$(/usr/bin/id -u -- @user@)" \
    /usr/bin/sudo --user=@user@ -- \
    /usr/bin/defaults -currentHost write @lib_escapeShellArg_domain@ @lib_escapeShellArg_key@ \
    -bool @boolValue@
fi
