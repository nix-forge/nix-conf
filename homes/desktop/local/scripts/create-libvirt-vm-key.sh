# shellcheck shell=sh
set -eu
umask 0077

@mkdir@ -p @sshDir@ @stateDir@
@chmod@ 700 @sshDir@ @stateDir@

if [ ! -f @keyFile@ ]; then
  @sshKeygen@ -t ed25519 -a 100 -N "" -C 'local libvirt development guests' -f @keyFile@
fi

if [ ! -f @publicKeyFile@ ]; then
  @sshKeygen@ -y -f @keyFile@ >@publicKeyFile@
fi

@chmod@ 600 @keyFile@
@chmod@ 644 @publicKeyFile@
