{ pkgs, myLib, ... }:
let
  inherit (myLib.configs) connectHomeDarwin;
in
{
  imports = [
    (connectHomeDarwin "ianmh@macbook-pro-m4" {
      description = "Ian Holloway";
      shell = pkgs.nushell;
    })
  ];
}
