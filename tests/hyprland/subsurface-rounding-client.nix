{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "subsurface-rounding-client";
  version = "1";
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.wayland-scanner
  ];
  buildInputs = [ pkgs.wayland ];
  buildPhase = (import ../../lib/templates/text.nix) ./scripts/build-subsurface-rounding-client.sh {
    pkgs_wayland_protocols = pkgs.wayland-protocols;
    subsurface_rounding_client_c = ./subsurface-rounding-client.c;
  };
  installPhase = builtins.readFile ./scripts/install-subsurface-rounding-client.sh;
}
