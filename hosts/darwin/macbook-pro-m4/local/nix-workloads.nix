{ config, lib, ... }:
let
  settings = {
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 8;
    eval-cores = lib.mkForce 4;
  };
in
lib.mkMerge [
  (lib.mkIf config.determinateNix.enable { determinateNix.customSettings = settings; })
  (lib.mkIf (!config.determinateNix.enable) { nix.settings = settings; })
]
