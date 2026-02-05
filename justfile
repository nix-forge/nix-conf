set shell := ["/usr/bin/env", "bash", "-c"]

default:
    @just --list --justfile {{ justfile() }}

[group('Flake')]
update input="":
    nix flake update {{ input }}

[group('Flake')]
dev-update input="":
    nix flake update {{ input }}

[group('Flake')]
check:
    nix flake check --no-allow-import-from-derivation

[group('Flake')]
show:
    nix flake show

[group('Maintenance')]
fmt:
    nix fmt

[group('Maintenance')]
verify:
    nix store verify --all
