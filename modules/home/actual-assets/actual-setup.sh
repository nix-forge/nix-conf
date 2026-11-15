# shellcheck shell=sh
set -eu

umask 0077
@mkdir@ -p @configDir@ @stateDir@ @dataDir@ @serverFiles@ @userFiles@
@chmod@ 700 @configDir@ @stateDir@ @dataDir@ @serverFiles@ @userFiles@
@install@ -m 600 @generatedConfig@ @configFile@
