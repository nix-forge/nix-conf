# shellcheck shell=bash
[[ $1 == hook && $2 == bash ]]
printf '%s\n' 'export DIRENV_FIXTURE=1'
