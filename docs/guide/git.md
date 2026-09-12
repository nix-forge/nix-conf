# Reuse the Git defaults

The repository's Git module configures aliases, branch defaults, readable diffs,
and platform-specific credential helpers. It does not set your author identity.
Read the [complete module](https://github.com/nix-forge/nix-conf/blob/main/modules/home/dev/git.nix)
before importing its preferences.

Add the configuration repository as a source input in your existing flake:

```nix
inputs.nix-conf-source = {
  url = "github:nix-forge/nix-conf";
  flake = false;
};
```

Commit the resulting lockfile so your configuration uses a specific revision.
An input with `flake = false` exposes source files without evaluating the full
workstation flake. These three recipes do not need the repository's submodules.

In a Home Manager module where that input is in scope:

```nix
{
  imports = [ (inputs.nix-conf-source + "/modules/home/dev/git.nix") ];
}
```

Pass the input through your existing `extraSpecialArgs` if that is how your
configuration supplies flake inputs. You do not need nix-config-framework to
import this ordinary Home Manager module.

Build your home configuration and inspect its generated Git file before
activation. The module sets `init.defaultBranch = "main"` and supplies the
`st` alias. It selects libsecret on Linux and Keychain on macOS; a desktop
credential backend must actually be available for credential storage to work.

A local override can keep your preferred default branch:

```nix
{ lib, ... }: {
  programs.git.settings.init.defaultBranch = lib.mkForce "trunk";
}
```

Use an override only for a deliberate disagreement with the shared setting.
Do not set a fake author identity to make the tutorial pass. Set your own public
identity separately when you are ready to make commits.

The `public-guide-recipes` check imports this module in a separate Home Manager
configuration and inspects its result. See [validation](support.md).
