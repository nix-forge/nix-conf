# Native proof for the current input, without accepting its installed guard.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  system = "x86_64-linux";
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  unpatched = flake.inputs.hyprland.packages.${system}.hyprland;
  installedFix = import ../hyprland-subsurface.nix { };
  patched = installedFix.apply unpatched;
  proof = import ../../../tests/hyprland/subsurface-parent-lifetime-vm.nix;
in
assert flake.inputs.hyprland.rev == "76edafffc68951a66b094806659ac4823e22c624";
assert patched.drvPath != unpatched.drvPath;
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    hyprlandRevision = flake.inputs.hyprland.rev;
    baselinePackage = unpatched.drvPath;
    repairedPackage = patched.drvPath;
    sourcePath = toString unpatched.src;
    baselineIsUnmodified = true;
    installedGuardMatchesInput = installedFix.reviewedRevision == flake.inputs.hyprland.rev;
    proofChangesInstalledGuard = false;
  };
  hyprlandParent = proof {
    inherit pkgs unpatched;
    patched = unpatched;
    parentOnly = true;
  };
  hyprland = proof { inherit pkgs unpatched patched; };
}
