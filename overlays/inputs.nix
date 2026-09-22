{ inputs }:
let
  fixes = import ./temporary {
    inherit inputs;
    inherit (inputs.nixpkgs) lib;
  };
in
inputs
// {
  determinate = inputs.determinate // {
    nixosModules = inputs.determinate.nixosModules // {
      default = fixes.apply "determinate-sentry-module" inputs.determinate;
    };
  };
  helium-browser-darwin = inputs.helium-browser-darwin // {
    packages = inputs.helium-browser-darwin.packages // {
      aarch64-darwin = inputs.helium-browser-darwin.packages.aarch64-darwin // {
        default = fixes.apply "helium-darwin-install" inputs.helium-browser-darwin.packages.aarch64-darwin.default;
      };
      x86_64-darwin = inputs.helium-browser-darwin.packages.x86_64-darwin // {
        default = fixes.apply "helium-darwin-install" inputs.helium-browser-darwin.packages.x86_64-darwin.default;
      };
    };
  };
}
