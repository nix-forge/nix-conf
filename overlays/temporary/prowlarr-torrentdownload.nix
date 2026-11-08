{ pkgs, ... }: {
  reason = "TorrentDownload drops music title separators and fails searches containing apostrophes.";
  upstream = "https://github.com/Prowlarr/Indexers/blob/ecede5c247d8e31fa156ff49a8921c78327c5b5d/definitions/v11/torrentdownload.yml";
  removal = "The pinned definition normalizes apostrophe searches and returns parseable music release titles; repeat the Lidarr release-search regression before removal.";
  # Review Cardigann parser changes with nixpkgs. The definition itself remains
  # independently pinned by its fetch hash, and patch application fails on drift.
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    source:
    pkgs.runCommand "torrentdownload-music-definition"
      {
        nativeBuildInputs = [
          pkgs.patch
          (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
        ];
      }
      (
        (import ../../lib/templates/text.nix) ./scripts/torrentdownload-music-definition.sh {
          inherit source;
          patches_prowlarr_torrentdownload_patch = ./patches/prowlarr-torrentdownload.patch;
          tests_prowlarr_torrentdownload_py = ./tests/prowlarr_torrentdownload.py;
        }
      );
}
