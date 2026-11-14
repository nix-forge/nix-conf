# shellcheck shell=bash
export WORKSTATION_TEST_DISK_COMMAND=@diskAdmissionCommand@
exec bash @fixtures@/check-workstation-task.sh @policy@
