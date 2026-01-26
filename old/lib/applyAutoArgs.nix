{ lib, ... }:
fn: attrs:
let
  fnArgs = lib.functionArgs fn;
  autoArgs = builtins.intersectAttrs fnArgs attrs;
in
fn autoArgs
