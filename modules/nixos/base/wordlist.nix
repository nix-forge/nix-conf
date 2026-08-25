{ config, lib, ... }:
let
  cfg = config.environment.wordlistBaseline;
in
{
  options.environment.wordlistBaseline.enable = lib.mkEnableOption ''
    a deterministic, general-purpose system wordlist
  '';

  config = lib.mkIf cfg.enable {
    # The upstream NixOS wordlist module merges its input files, trims entries,
    # sorts them, and removes duplicates into an immutable store path. It then
    # publishes that path as WORDLIST for command-line consumers.
    environment.wordlist.enable = true;

    assertions = [
      {
        assertion = config.environment.wordlist.lists ? WORDLIST;
        message = "environment.wordlistBaseline requires a standard WORDLIST entry; select its language and source in host-local configuration.";
      }
      {
        assertion = config.environment.wordlist.lists.WORDLIST != [ ];
        message = "environment.wordlistBaseline requires WORDLIST to contain at least one immutable text word source.";
      }
    ];

    # A plain text wordlist is useful for CLI/document tooling, but it is not a
    # spell-check engine and must not be mistaken for one. Keep Hunspell/Aspell
    # language dictionaries with their document/editor consumers, and keep
    # password-audit corpora or mutation lists out of a general desktop image.
    # Those databases have a different threat model, storage cost, and access
    # policy. Language choice and any project-specific terms are host-local.
  };
}
