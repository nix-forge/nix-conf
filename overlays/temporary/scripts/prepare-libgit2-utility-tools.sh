# shellcheck shell=bash
substituteInPlace tests/util/process/env.c \
  --replace-fail /usr/bin/env @env@
substituteInPlace tests/util/process/start.c \
  --replace-fail '"/usr/bin/false"' '"@false@"' \
  --replace-fail '"/bin/false"' '"@false@"' \
  --replace-fail /bin/cat @cat@ \
  --replace-fail /bin/pwd @pwd@
