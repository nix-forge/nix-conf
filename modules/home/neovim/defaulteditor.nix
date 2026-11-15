{ lib, ... }: {
  imports = [ ./default.nix ];
  home.sessionVariables.EDITOR = lib.mkDefault "nvim";
}
