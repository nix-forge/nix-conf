# shellcheck shell=bash
@syntaxCheck@ "$1"
@shellcheck@ --shell=bash @shellcheckFlags@ "$1"
