# The root flake, feature catalog, validation manifest, and platform contracts
# must describe the same supported systems. Keep this list independent of
# flake-parts so it can also be imported by the development partition.
[
  "x86_64-linux"
  "aarch64-linux"
  "aarch64-darwin"
]
