_: {
  reason = "QEMU's re-exec signal handling breaks the inherited ignored-SIGCHLD fixture in ARM nix-seal builds.";
  upstream = "https://github.com/nix-forge/nix-seal/blob/main/crates/nix-seal-runtime/tests/child.rs";
  removal = "The unmodified ARM package passes the inherited ignored-SIGCHLD fixture under QEMU; native package checks remain unchanged.";
  # Nixpkgs owns QEMU and the Cargo test hook. The exact fixture is guarded
  # separately because nix-seal is a local path input with independent changes.
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0.1.0-alpha.1";
    until = "0.1.0-alpha.2";
  };
  apply =
    package:
    if
      builtins.hashFile "sha256" (package.src + "/crates/nix-seal-runtime/tests/child.rs")
      != "37b653834381891cf2cff369fdcce90827c87945f48a86b5ae2c8c9765496f3d"
    then
      throw "Review nix-seal's inherited SIGCHLD fixture before excluding its emulated case"
    else
      package.overrideAttrs (old: {
        checkFlags = (old.checkFlags or [ ]) ++ [ "--skip=ignored_sigchld_reports_lost_ownership" ];
      });
}
