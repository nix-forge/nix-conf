# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
cp @orderingHome_config_xdg_configFile_systemd_user_name_service@ units/@name@.service
ln -s ../@name@.service units/graphical-session.target.wants/@name@.service
