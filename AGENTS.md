# Repository instructions

## Desktop build placement

Run the full `nixosConfigurations.desktop` build on the host named `desktop`.
From another host, use `just desktop-build` for a build with dry activation or
`just desktop-deploy` to build and activate. Evaluation-only commands may run
anywhere. The native Linux builder remains available for isolated Linux
packages and checks, not the desktop system closure.
