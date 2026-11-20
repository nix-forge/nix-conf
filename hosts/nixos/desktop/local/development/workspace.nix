{
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  # The helper supports activating just this rule without switching unrelated
  # host changes. A full host activation includes the same rule in its ruleset.
  ingress = writeShellApplication {
    name = "workspace-ingress";
    runtimeInputs = [ pkgs.nftables ];
    text = ''
      rules="$(nft list chain inet nixos-fw input-allow)"
      if [[ $rules == *'comment "local workspace ingress"'* ]]; then
        exit 0
      fi
      nft insert rule inet nixos-fw input-allow iifname '"virbr-mgmt"' ip saddr 192.168.123.12 ip daddr 192.168.123.1 tcp dport '{ 8443, 8444 }' accept comment '"local workspace ingress"'
    '';
  };
  dropIn = pkgs.writeText "workspace-ingress.conf" ''
    [Service]
    ExecStartPost=${lib.getExe ingress}
    ExecReload=${lib.getExe ingress}
  '';
  ingressPackage = pkgs.linkFarm "workspace-ingress" {
    "bin/workspace-ingress" = lib.getExe ingress;
    "share/systemd/workspace-ingress.conf" = dropIn;
  };
in
{
  # Admit only the fixed management guest to the two private service listeners.
  networking.firewall.extraInputRules = lib.mkOrder 450 ''
    iifname "virbr-mgmt" ip saddr 192.168.123.12 ip daddr 192.168.123.1 tcp dport { 8443, 8444 } accept comment "local workspace ingress"
  '';
  system.build.workspaceIngress = ingressPackage;
}
