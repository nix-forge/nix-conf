{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  program = pkgs.writers.writePython3 "workstation-nix-local" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/workstation_nix.py;
  runtime = (pkgs.formats.json { }).generate "workstation-nix-runtime.json" {
    runner = lib.getExe' config.lib.workstationTask "workstation-task";
    nix = lib.getExe' osConfig.nix.package "nix";
    cores = osConfig.nix.settings.cores;
    maxJobs = osConfig.nix.settings.max-jobs;
    bounded = osConfig.workstation.workloads.bounded;
  };
  command = pkgs.writeShellApplication {
    name = "workstation-nix";
    text = ''
      exec ${program} --runtime-config ${runtime} "$@"
    '';
  };
in
{
  home.packages = [ command ];
  lib.workstationNix = command;
  home.activation.workstationNixPreview = lib.hm.dag.entryAfter [ "installPackages" ] ''
    nixProfileRemove workstation-nix-preview
  '';
}
