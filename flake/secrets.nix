{ config, myLib, ... }:
let
  allSecrets = import ../secrets { inherit myLib; };
  inventory = config.nixConfigFramework.inventory;
in
{
  flake.secretIndex = myLib.secrets.mkSecretctlIndex {
    secretsTree = allSecrets;
    homeConfigs = inventory.homes;
    hostConfigs = inventory.hosts;
  };
}
