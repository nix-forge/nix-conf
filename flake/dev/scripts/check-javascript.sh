# shellcheck shell=bash
runHook preCheck
npm run typecheck
npm run lint
npm run format:check
METABRAINZ_EXTENSION=@metabrainzExtension@/metabrainz.js npm test
runHook postCheck
