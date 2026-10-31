{ pkgs, inputs }:
let
  system = pkgs.stdenv.hostPlatform.system;
  evaluate =
    determinate:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs.inputs = inputs // {
        inherit determinate;
      };
      modules = [
        (import ../../modules/shared/determinate.nix).nixos
        {
          nixpkgs.pkgs = pkgs;
          system.stateVersion = "26.05";
        }
      ];
    };
  evaluated = evaluate inputs.determinate;
  package = evaluated.config.nix.package;
  command = "@${
    inputs.determinate.packages.${system}.default
  }/bin/determinate-nixd determinate-nixd --nix-bin ${package}/bin daemon";
in
# Exercise the module with an ordinary package set and no repository overlay.
# Determinate owns the package assignment at normal module priority.
assert evaluated.pkgs.nix.drvPath == pkgs.nix.drvPath;
assert evaluated.options.nix.package.highestPrio == 100;
assert package.drvPath == inputs.determinate.inputs.nix.packages.${system}.default.drvPath;
assert
  evaluated.config.systemd.services.nix-daemon.serviceConfig.ExecStart == [
    ""
    command
  ];
package
