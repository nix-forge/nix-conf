{ inputs, ... }:
let
  inherit (inputs) nixpkgs;
  inherit (nixpkgs) lib;

  # This defines the custom library and its functions. What happens below is that we extend `nixpkgs.lib` with
  # my own set of functions, designed to be used within this repository.
  # You will come to realize that this is an ugly solution. The lib directory and the contents of this file
  # are frustratingly convoluted, and lib.extend cannot handle merging parent attributes (e.g self.modules
  # and super.modules will override each other, and not merge) so we cannot use the same names as nixpkgs.
  # This is a problem, as I want to use the same names as nixpkgs, but with my own functions. However there
  # is no clear solution to this problem, so we make all custom functions available under
  #  1. self.extendedLib, which is a set containing all custom parent attributes
  #  2. self.lib, which is the extended library.
  # There are technically no limitations to this approach, but if you want to avoid using shorthand aliases
  # to provided function, you would need to do something like `lib.extendedLib.aliases.foo` instead of
  # `lib.aliases.foo`, which is kinda annoying.
  extendedLib = lib // {
    bird = lib.extend inputs.bird-nix-lib.lib.overlay; # Bird Nix Lib
    cust = {
      nixos = import ./nixos;
      mkHome = import ./mkHome.nix;
      mkHost = import ./mkHost.nix;
      env = import ./env;
      builders = import ./builders.nix { inherit nixpkgs lib; };
      scanPaths = import ./scanPaths.nix { inherit lib; };
      files = import ./files { inherit lib; };
      applyAutoArgs = import ./applyAutoArgs.nix { inherit lib; };
      basePkgs = import ./basePkgs.nix;
    };
  };

in
{
  perSystem = {
    # Set the `lib` arg of the flake as the extended lib. If I am right, this should
    # override the previous argument (i.e. the original nixpkgs.lib, provided by flake-parts
    # as a reasonable default) with my own, which is the same nixpkgs library, but actually extended
    # with my own custom functions.
    imports = [ { _module.args.lib = extendedLib; } ];
  };

  flake = {
    # Also set `lib` as a flake output, which allows for it to be referenced outside
    # the scope of this flake. This is useful for when I want to refer to my extended
    # library from outside this flake, or if someone wants to access my functions
    # but that rarely happens, Ctrl+C and Ctrl+V is the developer way it seems.
    lib = extendedLib;
  };
}
