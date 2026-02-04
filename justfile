set shell := ["/usr/bin/env", "bash", "-c"]

default:
    @just --list --justfile {{ justfile() }}

[group('Flake')]
update input="":
    nix flake update {{ input }}

[group('Flake')]
check:
    nix flake check --accept-flake-config --no-allow-import-from-derivation

[group('Flake')]
show:
    nix flake show

[group('Maintenance')]
fmt:
    nix fmt

[group('Maintenance')]
verify:
    nix store verify --all
