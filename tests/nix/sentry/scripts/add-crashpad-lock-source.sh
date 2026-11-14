# shellcheck shell=bash
cp @crashpad_lock_cc@ nix-conf-crashpad-lock.cc
cat @cmakeSource@ >>CMakeLists.txt
