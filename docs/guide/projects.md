# Reuse the part you need

The related repositories have separate interfaces and release histories. You can
use a package without adopting the workstation, or organize targets without
adopting its secret policy.

| Project | Start here |
| --- | --- |
| [nix-config-framework](https://github.com/nix-forge/nix-config-framework) | [Minimal consumer and setup](https://github.com/nix-forge/nix-config-framework/blob/main/docs/getting-started.md) |
| [nixpkgs-personal](https://github.com/nix-forge/nixpkgs-personal) | [Package catalog](https://github.com/nix-forge/nixpkgs-personal/blob/main/docs/catalog.md) |
| [nix-seal](https://github.com/nix-forge/nix-seal) | [Maturity and provider choice](secrets.md) |
| [vpn-confinement](https://github.com/nix-forge/vpn-confinement) | [Tested application recipe](https://nix-forge.github.io/vpn-confinement/guides/transmission/) |
| [nix-forge CI](https://github.com/nix-forge/ci) | Shared Nix validation workflows and their permission contracts |

Package platform availability and licenses differ. Follow the package's catalog
entry and usage instructions. NUR registration is a separate publication step;
until it is accepted, the direct flake remains the documented interface.

Report problems to the repository that owns the behavior. Include the package
or module, configuration revision, Nixpkgs revision, platform, and reproduction.
