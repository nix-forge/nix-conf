{
  perSystem =
    { pkgs, ... }:
    let
      secretctlPkg = pkgs.writeShellApplication {
        name = "secretctl";
        runtimeInputs = [
          pkgs.python3
          pkgs.age
          pkgs.git
          pkgs.nix
        ];
        text = ''
          repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          export SECRETCTL_REPO_ROOT="$repo_root"
          exec ${pkgs.python3}/bin/python3 "${../../scripts/secretctl.py}" "$@"
        '';
      };
    in
    {
      packages.secretctl = secretctlPkg;

      apps.secretctl = {
        type = "app";
        program = "${pkgs.lib.getExe secretctlPkg}";
      };
    };
}
