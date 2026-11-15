{ lib, inputs, ... }: {
  nixpkgs.overlays = [ inputs.nixpkgs-personal.overlays.default ];
  nix.caches.raspberry-pi.enable = true;
  # The U-Boot boot path installs device trees from the vendor firmware.
  # The vendor's cached kernel does not expose Nixpkgs' buildDTBs flag.
  hardware.deviceTree.enable = false;
  # The same cached kernel stores its boot image as Image but does not
  # expose the target attribute expected by the newer NixOS module.
  system.boot.loader.kernelFile = lib.mkForce "Image";
}
