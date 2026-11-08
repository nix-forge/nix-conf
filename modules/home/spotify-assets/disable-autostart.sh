# shellcheck shell=bash
run /bin/launchctl disable "gui/$(/usr/bin/id -u)/com.spotify.client.startuphelper"
