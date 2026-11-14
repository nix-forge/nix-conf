{
  config,
  lib,
  pkgs,
  ...
}:
let
  policy = config.workstation.workloads.bounded;
  user = config.users.users.ianmh;
  package = import ../../../../modules/home/services/workstation-jobs-assets/host-check-package.nix {
    inherit pkgs;
    inherit (policy) minimumMiB maximumMiB;
    inherit (user) uid;
    gid = config.users.groups.${user.group}.gid;
  };
in
{
  system.build.workstationHostCheck = package;
  security.sudo.extraRules = [
    {
      users = [ "ianmh" ];
      runAs = "root";
      commands = [
        {
          command = lib.getExe' package "workstation-host-check";
          options = [
            "NOPASSWD"
            "NOSETENV"
          ];
        }
      ];
    }
  ];
}
