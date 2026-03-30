{
  perSystem =
    { pkgs, self', ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages =
          (with pkgs; [
            nh
            just

            shellcheck
            shfmt

            vfkit
            tailscale

            bashInteractive
          ])
          ++ [ self'.packages.vmnet-helper ];
      };
    };
}
