inputs: config: {
  inherit config;
  overlays = [ (import ../../../overlays { inherit inputs; }) ];
}
