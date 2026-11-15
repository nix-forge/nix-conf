# Host policy stays in the module; this package can also be built for a scoped rollout.
{
  pkgs,
  settings,
  nixPackage ? pkgs.nix,
}:
let
  inherit (pkgs) lib;
  assets = ./.;
  python = pkgs.writers.writePython3Bin "workstation-job-runtime" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (assets + /workstation_job.py);
  memoryController = pkgs.writers.writePython3 "workstation-memory" {
    libraries = [ pkgs.python3Packages.dbus-next ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (assets + /workstation_memory.py);
  configuration = pkgs.writeText "workstation-jobs-config.json" (
    builtins.toJSON (
      settings
      // {
        allocationVersion = 1;
        memoryController = toString memoryController;
        pueue = lib.getExe' pkgs.pueue "pueue";
        pueued = lib.getExe' pkgs.pueue "pueued";
        nixStore = lib.getExe' nixPackage "nix-store";
        bubblewrap = if pkgs.stdenv.hostPlatform.isLinux then lib.getExe pkgs.bubblewrap else "";
        ps = if pkgs.stdenv.hostPlatform.isLinux then lib.getExe' pkgs.procps "ps" else "/bin/ps";
        systemdRun =
          if pkgs.stdenv.hostPlatform.isLinux then lib.getExe' pkgs.systemd "systemd-run" else "";
        systemctl = if pkgs.stdenv.hostPlatform.isLinux then lib.getExe' pkgs.systemd "systemctl" else "";
        path = lib.makeBinPath (
          [
            pkgs.coreutils
            nixPackage
            pkgs.bash
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.systemd
            pkgs.util-linux
          ]
        );
      }
    )
  );
  client = pkgs.writeShellApplication {
    name = "workstation-job";
    text = ''exec ${lib.getExe' python "workstation-job-runtime"} --config ${configuration} "$@"'';
  };
in
pkgs.symlinkJoin {
  name = "workstation-jobs";
  paths = [
    client
    python
  ];
  passthru = {
    inherit configuration;
    inherit (pkgs) pueue;
  };
}
