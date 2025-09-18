{
  # Imports for constructing a final flake to be built.
  imports = [
    # Imported
    # inputs.flake-parts.flakeModules.easyOverlay

    # ./apps # apps provided by the flake
    ./checks # checks that are performed on `nix flake check`
    ./lib # extended library on top of `nixpkgs.lib`
    ./tree.nix # tree structure of the flake that imports leafs (files)
    # ./modules # nixos and home-manager modules provided by this flake
    # ./pkgs # packages exposed by the flake
    # ./pre-commit # pre-commit hooks, performed before each commit inside the devShell
    # ./templates # flake templates

    # ./args.nix # args that are passed to the flake, moved away from the main file
    # ./deployments.nix # deploy-rs configurations for active hosts
    ./fmt.nix # various formatter configurations for this flake
    # ./iso-images.nix # local installation media
    ./git-hooks.nix # git hooks for this repo
    ./shell.nix # devShells exposed by the flake
  ];
}
