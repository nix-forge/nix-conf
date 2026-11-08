{ lib, ... }: {
  reason = "Codex app discovery ignores the selected Home Manager bundle and incorrectly enters installer fallback.";
  upstream = "https://github.com/openai/codex/blob/086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a/codex-rs/cli/src/desktop_app/mac.rs";
  removal = "The unmodified CLI supports an explicit canonical application bundle while retaining OpenAI signature verification and refusing installer fallback for an invalid explicit path.";
  inputPath = [ "nixpkgs-personal" ];
  # This local path input has no Git revision; the actual fetched CLI source is
  # independently guarded below, alongside the package version and patch context.
  reviewedRevision = "<unversioned input>";
  affectedVersions = {
    from = "0.167.0";
    until = "0.168.0";
  };
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/codex-managed-app.patch ];
      prePatch =
        assert lib.assertMsg (
          (old.src.rev or null) == "086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a"
        ) "Review the Codex managed-app repair against the changed CLI source";
        old.prePatch or "";
    });
}
