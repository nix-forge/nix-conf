# shellcheck shell=bash
set -eu
# The VM creates this FIFO before startup. Opening it blocks until the test
# supplies the network-completion token, including when the writer arrives first.
IFS= read -r network_state </run/fixture-network-online
test "$network_state" = online
@pkgs_coreutils@/bin/cp @fixtureDatabase@ /var/lib/clamav/fixture.ndb
