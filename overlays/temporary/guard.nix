{ lib }:
# Check the incoming value; package fixes may also guard its version.
{
  name,
  reason,
  upstream,
  removal,
  reviewedRevision,
  affectedVersions ? null,
  ...
}:
currentRevision: value:
let
  fail =
    detail:
    throw ''
      Temporary upstream fix '${name}' needs review: ${detail}
      Reason: ${reason}
      Upstream: ${upstream}
      Remove when: ${removal}
      Review overlays/temporary/${name}.nix. Do not advance the guard without checking the unmodified package.
    '';
  version = value.version or null;
  rangeValid =
    affectedVersions == null
    || (
      affectedVersions ? from
      && affectedVersions ? until
      && lib.versionOlder affectedVersions.from affectedVersions.until
    );
  inRange =
    affectedVersions == null
    || (
      version != null
      && lib.versionAtLeast version affectedVersions.from
      && lib.versionOlder version affectedVersions.until
    );
in
if reason == "" || upstream == "" || removal == "" then
  fail "missing lifecycle metadata"
else if reviewedRevision == "" || currentRevision != reviewedRevision then
  fail "upstream revision changed from ${reviewedRevision} to ${currentRevision}"
else if !rangeValid then
  fail "expected a nonempty version interval [from, until)"
else if !inRange then
  fail "incoming version ${
    if version == null then "<missing>" else version
  } is outside [${affectedVersions.from}, ${affectedVersions.until})"
else
  value
