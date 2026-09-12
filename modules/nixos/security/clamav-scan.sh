set -euo pipefail

scanner=$1
shift
if (( $# == 0 )); then
  echo "ClamAV scan requires at least one input directory" >&2
  exit 2
fi

# Match the baseline's no-follow symlink policy. NUL delimiters preserve every
# filename; bounded batches retain clamdscan's descriptor passing and workers.
# pipefail keeps traversal failures visible, and xargs returns nonzero for both
# malware detections and scanner errors while processing the remaining batches.
find -P "$@" -type f -print0 |
  xargs -0 -r -n 128 "$scanner" --multiscan --fdpass --infected --allmatch
