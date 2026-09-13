# Add interactive file search

The [fzf module](https://github.com/nix-forge/nix-conf/blob/main/modules/home/shells/fzf.nix)
adds fuzzy selection and shell integration. It is an ordinary Home Manager module.
Use the source input from the [Git recipe](git.md), then import:

```nix
{
  imports = [
    (inputs.nix-conf-source + "/modules/home/shells/fzf.nix")
    (inputs.nix-conf-source + "/modules/home/shells/integration.nix")
  ];
}
```

The integration module enables integrations only for shells your home actually
enables. This avoids initializing an unused shell or requiring its integration
dependencies. Enable the shell you actually use in your own home configuration. Build first,
then open a new shell after activation so its integration is loaded. In a small
sample directory, type `fzf` and filter the listed filenames. Press Escape to
cancel without selecting a file.

Read the module's configured commands and keybindings before using it in large
or sensitive directories. The caller owns the directory being searched. This
recipe changes the selector configuration; it does not index your workstation
or upload filenames.

The `public-guide-recipes` check imports the module outside the personal
profiles. That validates its Home Manager configuration and generated settings;
interactive terminal behavior still needs a real shell session.
