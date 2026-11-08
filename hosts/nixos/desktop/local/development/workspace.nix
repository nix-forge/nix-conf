{ lib, pkgs, ... }:
let
  # The helper supports activating just this rule without switching unrelated
  # host changes. A full host activation includes the same rule in its ruleset.
  ingress = pkgs.writeShellApplication {
    name = "workspace-ingress";
    runtimeInputs = [ pkgs.nftables ];
    text = builtins.readFile ./scripts/workspace-ingress.sh;
  };
  dropIn = pkgs.writeText "workspace-ingress.conf" ''
    [Service]
    ExecStartPost=${lib.getExe ingress}
    ExecReload=${lib.getExe ingress}
  '';
  ingressPackage = pkgs.symlinkJoin {
    name = "workspace-ingress";
    paths = [ ingress ];
    postBuild = (import ../../../../../lib/templates/text.nix) ./scripts/workspace-ingress-body.sh {
      inherit dropIn;
    };
  };
in
{
  # Admit only the fixed management guest to the two private service listeners.
  networking.firewall.extraInputRules = lib.mkOrder 450 ''
    iifname "virbr-mgmt" ip saddr 192.168.123.12 ip daddr 192.168.123.1 tcp dport { 8443, 8444 } accept comment "local workspace ingress"
  '';
  system.build.workspaceIngress = ingressPackage;
}
