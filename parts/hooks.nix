{
  nixfmt-rfc-style.enable = true;
  statix.enable = true;
  statix.pass_filenames = true;
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
  prettier.enable = true;
  yamllint.enable = true;
}
