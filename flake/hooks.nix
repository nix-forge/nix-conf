{
  nixfmt-rfc-style.enable = true;
  statix.enable = true;
  # Loop over staged files so statix handles one TARGET at a time
  statix.pass_filenames = true;
  statix.require_serial = true;
  statix.entry = "bash -lc 'err=0; for f in \"$@\"; do [ -f \"$f\" ] || continue; statix check --format errfmt -- \"$f\" || err=1; done; exit $err'";
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

  markdownlint.enable = true;
  markdownlint.args = [ "--fix" ];
  markdownlint.after = [ "prettier" ];
  # Prefer wrapping prose via Prettier instead of enforcing MD013
  # markdownlint.settings.configuration = { MD013 = false; };
  prettier.enable = true;
  prettier.settings.prose-wrap = "always";
  yamllint.enable = true;

  # Ignore known public minisign keys flagged by ripsecrets
  ripsecrets.excludes = [ "^_nixOSModules/networking/dnscrypt-proxy.nix$" ];
}
