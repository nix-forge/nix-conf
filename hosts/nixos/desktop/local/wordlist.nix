{ pkgs, ... }: {
  environment.wordlistBaseline.enable = true;

  # The desktop uses US English. SCOWL's maintained, general-purpose list is
  # small enough for shell and document-tool lookup while avoiding a giant
  # corpus of obscure words, passwords, leaked credentials, or word mutations.
  # Add reviewed project terminology as a separate immutable file only when a
  # concrete local consumer needs it; never place secrets in WORDLIST.
  environment.wordlist.lists.WORDLIST = [ "${pkgs.scowl}/share/dict/words.txt" ];
}
