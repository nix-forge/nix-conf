{
  tree,
  pkgs,
  inputs,
  ...
}:
let
  darwinDir = tree.configs.home;
  sharedDir = tree.configs.shared;
  install = pkg: { environment.systemPackages = [ pkg ]; };
in
with darwinDir;
[
  # base.base

  (install firefox)
  (install vscode)
]
