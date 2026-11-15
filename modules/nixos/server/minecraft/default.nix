{ lib, ... }: {
  # Use the native NixOS interface for packages, JVM options, ports and
  # server properties. Callers must accept the EULA explicitly; the upstream
  # module asserts that requirement before building an enabled server.
  services.minecraft-server.enable = lib.mkDefault true;
}
