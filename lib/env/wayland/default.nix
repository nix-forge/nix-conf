rec {
  base = import ./base.nix;
  electron = import ./electron.nix;
  java = import ./java.nix;
  qt = import ./qt.nix;

  all = base // electron // java // qt;
}
