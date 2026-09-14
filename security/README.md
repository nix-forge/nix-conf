# Security evidence

This directory contains public, machine-readable security evidence. It never
contains credentials, private host data, or plaintext secrets.

`vex.json` is an OpenVEX document. An empty `statements` array means that this
repository has no current non-affectability assertion to publish. Add a
statement only after reviewing a dependency vulnerability against the actual
module and release scope. Security issues that affect users belong in
[SECURITY.md](../SECURITY.md) and GitHub private vulnerability reporting.
