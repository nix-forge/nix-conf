# Only namespace setup is privileged; user invocation data is decoded after setuid.
{
  pkgs,
  uid,
  gid,
  minimumMiB,
  maximumMiB,
}:
let
  inherit (pkgs) lib;
  source = pkgs.writeText "workstation-host-check.py" (builtins.readFile ./workstation_host_check.py);
  configuration = pkgs.writeText "workstation-host-check-config.json" (
    builtins.toJSON {
      inherit
        uid
        gid
        minimumMiB
        maximumMiB
        ;
      bubblewrap = lib.getExe pkgs.bubblewrap;
      setpriv = lib.getExe' pkgs.util-linux "setpriv";
      python = lib.getExe pkgs.python3;
    }
  );
  helper = pkgs.writeTextFile {
    name = "workstation-host-check";
    destination = "/bin/workstation-host-check";
    executable = true;
    text = ''
      #!${lib.getExe pkgs.bash} -p
      exec ${lib.getExe pkgs.python3} -I ${source} --root ${configuration} "$@"
    '';
  };
  client = pkgs.writeShellScriptBin "workstation-host-check-client" ''
    exec ${lib.getExe pkgs.python3} -I ${source} --client ${lib.getExe' helper "workstation-host-check"} "$@"
  '';
in
pkgs.symlinkJoin {
  name = "workstation-host-check";
  paths = [
    helper
    client
  ];
}
