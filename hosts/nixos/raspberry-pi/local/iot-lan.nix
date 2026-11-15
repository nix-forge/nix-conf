_:
let
  network = builtins.fromJSON (builtins.readFile ../../../shared/local/network.json);
  interface = "eth0.${toString network.iotVlanId}";
in
{
  # Some IoT devices accept control only from their own subnet. This optional
  # tagged interface gives the Pi a local source address without moving its
  # management, Homebridge UI, or default route off the Servers network.
  systemd.network.netdevs."20-iot" = {
    netdevConfig = {
      Name = interface;
      Kind = "vlan";
    };
    vlanConfig.Id = network.iotVlanId;
  };
  systemd.network.networks."10-ethernet".networkConfig.VLAN = [ interface ];
  systemd.network.networks."20-iot" = {
    matchConfig.Name = interface;
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = false;
      MulticastDNS = false;
      LinkLocalAddressing = "no";
    };
    dhcpV4Config = {
      UseRoutes = false;
      UseDNS = false;
      UseNTP = false;
    };
    linkConfig.RequiredForOnline = "no";
  };
}
