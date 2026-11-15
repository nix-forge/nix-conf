# Keep the application source on its owning personal recipe; only choose the
# matched, immutable upstream dependency scope on native consumers.
{
  inputs,
  package,
  system,
}:
let
  upstream = import inputs.nixpkgs-apps { inherit system; };
in
if package.stdenv.buildPlatform == package.stdenv.hostPlatform then
  package.override { inherit (upstream) nodejs_24 nodejs-slim_24 brotli; }
else
  package
