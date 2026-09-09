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
  # Retiring the input replacement must require no change to the shared module.
  unpatched = evaluate (
    inputs.determinate
    // {
      nixosModules.default = import (inputs.determinate + "/modules/nixos.nix") (
        inputs.determinate.inputs // { self = inputs.determinate; }
      );
    }
  );
  package = evaluated.config.nix.package;
  command = "@${
    inputs.determinate.packages.${system}.default
  }/bin/determinate-nixd determinate-nixd --nix-bin ${package}/bin daemon";
in
# Exercise the module with an ordinary package set and no repository overlay.
# Determinate owns the package assignment at normal module priority.
assert evaluated.pkgs.nix.drvPath == pkgs.nix.drvPath;
assert evaluated.options.nix.package.highestPrio == 100;
assert unpatched.options.nix.package.highestPrio == 100;
assert
  unpatched.config.nix.package.drvPath
  == inputs.determinate.inputs.nix.packages.${system}.default.drvPath;
assert package.drvPath != inputs.determinate.inputs.nix.packages.${system}.default.drvPath;
assert package.tests ? crashpad-lock;
assert
  evaluated.config.systemd.services.nix-daemon.serviceConfig.ExecStart == [
    ""
    command
  ];
package
