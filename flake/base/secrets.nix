{ myLib, ... }:
{
  flake.secrets = import ../../secrets { inherit myLib; };
}
