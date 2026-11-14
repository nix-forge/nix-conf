# Ordinary outputs stay native. Cross compilation is an explicit platform pair.
platform:
let
  hostSystem = if builtins.isAttrs platform then platform.hostSystem else platform;
  buildSystem = if builtins.isAttrs platform then platform.buildSystem or hostSystem else hostSystem;
  linuxSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
in
if buildSystem == hostSystem then
  { system = hostSystem; }
else if builtins.elem buildSystem linuxSystems && builtins.elem hostSystem linuxSystems then
  {
    localSystem = buildSystem;
    crossSystem.config =
      if hostSystem == "aarch64-linux" then "aarch64-unknown-linux-gnu" else "x86_64-unknown-linux-gnu";
  }
else
  throw "Cross compilation requires a supported Linux build/host platform pair"
