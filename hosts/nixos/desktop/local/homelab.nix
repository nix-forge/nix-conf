{ inputs, ... }: {
  imports = [ inputs.nix-homelab.nixosModules.default ];

  # Apply the shared-desktop scheduling policy now. Media applications remain
  # disabled until the external mount, backup budget and VPN secrets are ready.
  homelab.profiles.desktop.enable = true;
}
