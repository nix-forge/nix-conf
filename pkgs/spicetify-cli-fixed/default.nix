{
  spicetify-cli,
  nodejs,
  esbuild,
}:
spicetify-cli.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    nodejs
    esbuild
  ];

  # Remove this once NixOS/nixpkgs#540416 reaches the pinned Nixpkgs revision.
  postBuild = (old.postBuild or "") + ''
    esbuild "$src/src/jsHelper/spicetifyWrapper/index.js" \
      --bundle \
      --format=iife \
      --legal-comments=none \
      --log-level=warning \
      --minify \
      --outfile=spicetifyWrapper.js \
      --sourcemap \
      --target=chrome108
  '';

  postInstall = (old.postInstall or "") + ''
    chmod -R u+w "$out/share/spicetify/jsHelper"
    install -m 644 spicetifyWrapper.js spicetifyWrapper.js.map "$out/share/spicetify/jsHelper"
  '';
})
