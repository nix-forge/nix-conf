{ pkgs, lib, ... }:
{
  nixfmt-rfc-style.enable = true;
  statix = {
    enable = true;
    pass_filenames = true;
    require_serial = true;
    entry = "${lib.getExe pkgs.bash} -lc 'err=0; for f in \"$@\"; do [ -f \"$f\" ] || continue; ${lib.getExe pkgs.statix} check --format errfmt -- \"$f\" || err=1; done; exit $err'";
  };
  deadnix.enable = true;
  deadnix.settings.edit = true;
  nil.enable = true;

  ripsecrets.enable = true;
  end-of-file-fixer.enable = true;
  trim-trailing-whitespace.enable = true;
  mixed-line-endings.enable = true;
  mixed-line-endings.args = [ "--fix=lf" ];
  check-merge-conflicts.enable = true;
  check-symlinks.enable = true;

  actionlint.enable = true;
  shellcheck.enable = true;
  shfmt.enable = true;
  shfmt.settings.simplify = true;

  markdownlint = {
    enable = true;
    args = [ "--fix" ];
    after = [ "prettier" ];
  };
  # Prefer wrapping prose via Prettier instead of enforcing MD013
  # markdownlint.settings.configuration = { MD013 = false; };
  prettier.enable = true;
  prettier.settings.prose-wrap = "always";
  yamllint.enable = true;

  # Ignore known public minisign keys flagged by ripsecrets
  # TODO: check if this is needed
  ripsecrets.excludes = [ "^nixosModules/networking/dnscrypt-proxy.nix$" ];
}
