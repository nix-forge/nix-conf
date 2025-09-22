{ callPackage, ... }:
{
  copilot = callPackage ./copilot { };
  copilot-chat = callPackage ./copilot-chat { };
}
