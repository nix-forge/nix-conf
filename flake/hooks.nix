{ lib, config, ... }:
{
  # Single formatter entrypoint: treefmt (fixes in place where supported)
  treefmt = {
    enable = true;
    name = "treefmt";
    pass_filenames = true;
    entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
  };

  # Non-formatting or generic whitespace hygiene (run after formatting)
  ripsecrets = {
    enable = true;
    after = [ "treefmt" ];
    # Ignore known public minisign keys flagged by ripsecrets
    excludes = [ "^nixosModules/networking/dnscrypt-proxy.nix$" ];
  };

  end-of-file-fixer = {
    enable = true;
    after = [ "treefmt" ];
  };
  trim-trailing-whitespace = {
    enable = true;
    after = [ "treefmt" ];
  };
  mixed-line-endings = {
    enable = true;
    args = [ "--fix=lf" ];
    after = [ "treefmt" ];
  };

  check-merge-conflicts.enable = true;
  check-symlinks.enable = true;

  # All language-specific formatters and linters run via treefmt; avoid duplication here.
}
