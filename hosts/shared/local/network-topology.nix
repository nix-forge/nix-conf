let
  network = builtins.fromJSON (builtins.readFile ./network.json);
in
{
  raspberryPi = {
    serverAddress = network.raspberryPiServerAddress;
    httpsSites = network.raspberryPiHttpsSites;
  };
}
