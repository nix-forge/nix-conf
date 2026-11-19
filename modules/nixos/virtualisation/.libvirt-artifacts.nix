{
  lib,
  myLib,
  pkgs,
  libvirtPackage,
}:
let
  inherit (lib) getExe getExe';
  controlPackage = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).libvirtControl;
  renderText = myLib.templates.renderText;
in
{
  mkControl =
    name: dir: mode: policy:
    let
      policyFile = (pkgs.formats.json { }).generate "${name}-policy.json" policy;
    in
    pkgs.writeTextFile {
      inherit name;
      destination = if dir == null then "" else "/${dir}/${name}";
      executable = true;
      text = "#!${getExe pkgs.bash}\nexec ${getExe controlPackage} ${lib.escapeShellArg mode} ${policyFile} \"$@\"\n";
    };

  validateXml =
    schema: name: source:
    pkgs.runCommand "validated-${name}-${schema}.xml" { } (
      renderText
        {
          name = "validate-libvirt-xml.sh";
          text = ''
            # shellcheck shell=bash
            # Nix builder/activation callers and rendered fragments provide external variables.
            # shellcheck disable=SC2154
            cp @source@ "$out"
            @validator@ "$out" @schema@
          '';
        }
        {
          inherit schema source;
          validator = getExe' libvirtPackage "virt-xml-validate";
        }
    );
}
