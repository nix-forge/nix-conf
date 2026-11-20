{ myLib, pkgs, ... }: {
  reason = "TorrentDownload drops music title separators and fails searches containing apostrophes.";
  upstream = "https://github.com/Prowlarr/Indexers/blob/ecede5c247d8e31fa156ff49a8921c78327c5b5d/definitions/v11/torrentdownload.yml";
  removal = "The pinned definition normalizes apostrophe searches and returns parseable music release titles; repeat the Lidarr release-search regression before removal.";
  # Review Cardigann parser changes with nixpkgs. The definition itself remains
  # independently pinned by its fetch hash, and patch application fails on drift.
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    source:
    pkgs.runCommand "torrentdownload-music-definition" { nativeBuildInputs = [ pkgs.patch ]; } (
      myLib.writers.renderBashText { inherit pkgs; }
        {
          name = "torrentdownload-music-definition.sh";
          text = ''
            # shellcheck shell=bash
            # Nix builder/activation callers and rendered fragments provide external variables.
            # shellcheck disable=SC2154
            cp @source@ torrentdownload.yml
            chmod u+w torrentdownload.yml
            patch --fuzz=0 -p1 <@patches_prowlarr_torrentdownload_patch@
            cp torrentdownload.yml "$out"
          '';
        }
        {
          inherit source;
          patches_prowlarr_torrentdownload_patch = ./patches/prowlarr-torrentdownload.patch;
        }
    );
}
