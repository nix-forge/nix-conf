# Add a host deliberately

The personal hosts are examples of integration, not portable hardware definitions.
First finish the [starter](first-configuration.md) and understand the
[architecture](architecture.md). Use the framework's
[minimal consumer](https://github.com/nix-forge/nix-config-framework/tree/main/examples/minimal)
when you are ready to organize several targets.

## NixOS

Install or prepare NixOS using the
[official manual](https://nixos.org/manual/nixos/stable/). Generate hardware
configuration for the actual machine. Do not reuse another host's filesystem,
disk, boot, or network identifiers.

In the framework layout, add `hosts/nixos/<HOSTNAME>/default.nix`. Start with a
small feature selection and the generated hardware module. Add a home profile
under `homes/`, then attach it using the framework's `homes.<login>.config`
contract. Consult the [target specification](https://github.com/nix-forge/nix-config-framework#target-specifications)
for the complete interface.

Evaluate and build before activating. Keep access to a previous generation and
a working recovery method. Add storage encryption, remote access, and secret
provisioning only after the basic target works and you have read their operational
guides. The public VM teaches composition without repartitioning hardware.

## Apple Silicon macOS

Use the [nix-darwin setup instructions](https://github.com/nix-darwin/nix-darwin#installing)
for an existing macOS account. Match your actual username and home directory.
Add a Darwin target under `hosts/darwin/` if using the framework, and build it
on a suitable Mac before activation. macOS permissions and native application
behavior require native testing; Linux evaluation cannot establish them.

## Keep the scope small

Add one feature at a time and verify its observable result. Keep hardware policy
in the host and ordinary user preferences in the home. Use a typed option when
multiple targets need a real variation, and keep one owner for each setting.

See [update and recovery](update-and-recover.md) before making this your daily
configuration.
