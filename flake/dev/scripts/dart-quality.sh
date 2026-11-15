# shellcheck shell=bash
# The builder supplies the output path.
# shellcheck disable=SC2154
python3 @checker@ @source@/lib/playback/media_kit_player_backend.dart @dart@ @fixture@ @analysisOptions@
touch "$out"
